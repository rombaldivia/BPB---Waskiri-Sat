/* -----------------------  main.c  ------------------------------ */
#include <stdio.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#include "esp_event.h"
#include "nvs_flash.h"
#include "esp_log.h"

/* UART */
#include "driver/uart.h"
#include "esp_vfs_dev.h"

/* BLE NimBLE */
#include "esp_nimble_hci.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/ble_gap.h"
#include "os/os_mbuf.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

/* LED */
#include "driver/gpio.h"
#include "esp_timer.h"

/* UART sensor */
#define US_UART_PORT   UART_NUM_2
#define US_TX_PIN      GPIO_NUM_17
#define US_RX_PIN      GPIO_NUM_16
#define US_UART_BAUD   9600

#define LED_PIN        GPIO_NUM_2

static const char *TAG = "BLE-UART";

static uint8_t  ble_addr_type;
static struct   ble_gap_adv_params adv_params;
static uint16_t conn_handle = BLE_HS_CONN_HANDLE_NONE;
static bool     subscribed  = false;
static uint16_t chr_val_handle;

/* Cola para notificaciones BLE */
static QueueHandle_t q_ble;

/* LED timer */
static esp_timer_handle_t led_timer;
static void led_off(void*) { gpio_set_level(LED_PIN, 1); }
static void blink_led(void)
{
    gpio_set_level(LED_PIN, 0);
    esp_timer_start_once(led_timer, 200 * 1000);
}

/* NOTIFY seguro (solo desde notify_task) */
static void ble_send(const char *txt)
{
    if (!subscribed || conn_handle == BLE_HS_CONN_HANDLE_NONE)
        return;

    struct os_mbuf *om = ble_hs_mbuf_from_flat(txt, strlen(txt));
    if (om) {
        ble_gatts_notify_custom(conn_handle, chr_val_handle, om);
        blink_led();
    }
}

/* ---------------- GATT ---------------- */
static int device_write(uint16_t, uint16_t,
                        struct ble_gatt_access_ctxt *ctxt, void*)
{
    printf("[APP->ESP32] %.*s\n", ctxt->om->om_len, ctxt->om->om_data);
    blink_led();
    return 0;
}

static int device_read(uint16_t, uint16_t,
                       struct ble_gatt_access_ctxt *ctxt, void*)
{
    const char *msg = "OK";
    os_mbuf_append(ctxt->om, msg, strlen(msg));
    return 0;
}

/* ⚠️ CAMBIO IMPORTANTE: ya NO duplicamos UUID 0xDEAD */
static const struct ble_gatt_svc_def gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = BLE_UUID16_DECLARE(0x0180),
        .characteristics = (struct ble_gatt_chr_def[]) {

            { .uuid      = BLE_UUID16_DECLARE(0xFEF4),
              .flags     = BLE_GATT_CHR_F_READ,
              .access_cb = device_read },

            { .uuid      = BLE_UUID16_DECLARE(0xDEAD),
              .flags     = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_NOTIFY,
              .access_cb = device_write,
              .val_handle = &chr_val_handle },

            { 0 }
        }
    },
    { 0 }
};

/* -------------- GAP events ---------------- */
static void ble_app_advertise(void);

static int ble_gap_event(struct ble_gap_event *e, void*)
{
    switch (e->type) {

    case BLE_GAP_EVENT_CONNECT:
        ESP_LOGI(TAG, "CONNECT: %s", e->connect.status == 0 ? "OK" : "FAIL");

        if (e->connect.status == 0) {
            conn_handle = e->connect.conn_handle;

            /* Parámetros estables para ESP-IDF 5.x */
            struct ble_gap_upd_params p = {
                .itvl_min = 24,
                .itvl_max = 40,
                .latency  = 0,
                .supervision_timeout = 500,
                .min_ce_len = 0,
                .max_ce_len = 0,
            };
            ble_gap_update_params(conn_handle, &p);

        } else ble_app_advertise();
        return 0;

    case BLE_GAP_EVENT_DISCONNECT:
        subscribed  = false;
        conn_handle = BLE_HS_CONN_HANDLE_NONE;
        ESP_LOGI(TAG, "DISCONNECT");
        ble_app_advertise();
        return 0;

    case BLE_GAP_EVENT_SUBSCRIBE:
        subscribed = e->subscribe.cur_notify;
        ESP_LOGI(TAG, "Subscribed = %d", subscribed);
        return 0;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        ble_app_advertise();
        return 0;

    default:
        return 0;
    }
}

static void ble_app_advertise(void)
{
    struct ble_hs_adv_fields f = {0};
    const char *name = ble_svc_gap_device_name();

    f.name = (uint8_t*)name;
    f.name_len = strlen(name);
    f.name_is_complete = 1;

    ble_gap_adv_set_fields(&f);

    memset(&adv_params, 0, sizeof(adv_params));
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;

    ble_gap_adv_start(ble_addr_type, NULL, BLE_HS_FOREVER,
                      &adv_params, ble_gap_event, NULL);
}

static void on_sync(void)
{
    ble_hs_id_infer_auto(0, &ble_addr_type);
    ble_app_advertise();
}

static void host_task(void*)
{
    nimble_port_run();
    nimble_port_freertos_deinit();
}

/* ---------------- UART SENSOR TASK ---------------- */
static void us_sensor_task(void *arg)
{
    uint8_t frame[4];
    char msg[32];

    for (;;) {
        int n = uart_read_bytes(US_UART_PORT, frame, 4, pdMS_TO_TICKS(20));

        if (n == 4 && frame[0] == 0xFF) {
            uint8_t sum = (frame[0]+frame[1]+frame[2]) & 0xFF;

            if (sum == frame[3]) {
                float dist = ((frame[1]<<8) | frame[2]) / 10.0f;

                snprintf(msg, sizeof(msg), "Dist: %.1f cm", dist);
                printf("%s\n", msg);

                /* SOLO copiar a la cola, NO enviar notify aquí */
                xQueueSend(q_ble, msg, 0);
            }
        }

        vTaskDelay(pdMS_TO_TICKS(30));
    }
}

/* -------------- BLE NOTIFY QUEUE TASK ---------------- */
static void notify_task(void *arg)
{
    char msg[64];

    while (1) {
        if (xQueueReceive(q_ble, msg, portMAX_DELAY)) {
            ble_send(msg);  // ahora sí enviamos NOTIFY
        }
    }
}

/* -------------- Inicialización BLE ---------------- */
static void connect_ble(void)
{
    ESP_ERROR_CHECK(nvs_flash_init());
    ESP_ERROR_CHECK(nimble_port_init());

    ble_svc_gap_device_name_set("BLE-Ultra");
    ble_svc_gap_init();
    ble_svc_gatt_init();

    ble_gatts_count_cfg(gatt_svcs);
    ble_gatts_add_svcs(gatt_svcs);

    ble_hs_cfg.sync_cb = on_sync;

    nimble_port_freertos_init(host_task);
}

/* ---------------- app_main ---------------- */
void app_main(void)
{
    /* UART0 console */
    setvbuf(stdout, NULL, _IONBF, 0);
    esp_log_level_set(TAG, ESP_LOG_INFO);

    /* LED */
    gpio_reset_pin(LED_PIN);
    gpio_set_direction(LED_PIN, GPIO_MODE_OUTPUT);
    gpio_set_level(LED_PIN, 1);

    const esp_timer_create_args_t args = {
        .callback = led_off,
        .name = "led_off"
    };
    ESP_ERROR_CHECK(esp_timer_create(&args, &led_timer));

    /* UART2 sensor */
    uart_config_t cfg = {
        .baud_rate = US_UART_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity    = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_APB
    };
    ESP_ERROR_CHECK(uart_driver_install(US_UART_PORT, 256, 0, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(US_UART_PORT, &cfg));
    ESP_ERROR_CHECK(uart_set_pin(US_UART_PORT,
                                 US_TX_PIN, US_RX_PIN,
                                 UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));

    /* Cola BLE */
    q_ble = xQueueCreate(10, 64);

    /* BLE */
    connect_ble();

    /* Tasks */
    xTaskCreate(us_sensor_task, "uart_sensor", 4096, NULL, 6, NULL);
    xTaskCreate(notify_task,    "ble_notify",  4096, NULL, 5, NULL);
}

