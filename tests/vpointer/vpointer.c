// Clique de verdade para os testes: um cursor virtual (wlr-virtual-pointer)
// dentro do Hyprland aninhado. Leva o cursor até o ponto e aperta um botão.
// Fala só com o WAYLAND_DISPLAY que recebe; quem chama (tests/nested.py)
// confere antes que ele é o da sessão de teste.
//
// Uso: vpointer X Y LARGURA ALTURA [left|right|middle|move]
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct wl_seat *seat;

static void global_add(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
                       uint32_t version) {
  (void)data;
  (void)version;
  if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0 && !manager)
    manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
  else if (strcmp(interface, wl_seat_interface.name) == 0 && !seat)
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
}

static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener registry_listener = {global_add, global_remove};

static uint32_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int main(int argc, char **argv) {
  if (argc < 5) {
    fprintf(stderr, "uso: vpointer X Y LARGURA ALTURA [left|right|middle|move]\n");
    return 2;
  }
  uint32_t x = (uint32_t)strtoul(argv[1], NULL, 10), y = (uint32_t)strtoul(argv[2], NULL, 10);
  uint32_t width = (uint32_t)strtoul(argv[3], NULL, 10), height = (uint32_t)strtoul(argv[4], NULL, 10);
  const char *what = argc > 5 ? argv[5] : "left";
  uint32_t button = BTN_LEFT;
  if (strcmp(what, "right") == 0) button = BTN_RIGHT;
  else if (strcmp(what, "middle") == 0) button = BTN_MIDDLE;

  struct wl_display *display = wl_display_connect(NULL);
  if (!display) {
    fprintf(stderr, "vpointer: não consegui abrir o WAYLAND_DISPLAY\n");
    return 1;
  }
  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  wl_display_roundtrip(display);
  if (!manager) {
    fprintf(stderr, "vpointer: o compositor não oferece zwlr_virtual_pointer_manager_v1\n");
    return 1;
  }

  struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
  zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), x, y, width, height);
  zwlr_virtual_pointer_v1_frame(pointer);
  wl_display_roundtrip(display);
  usleep(250 * 1000);  // o hover chega antes do clique, como com um mouse de verdade

  if (strcmp(what, "move") != 0) {
    zwlr_virtual_pointer_v1_button(pointer, now_ms(), button, WL_POINTER_BUTTON_STATE_PRESSED);
    zwlr_virtual_pointer_v1_frame(pointer);
    wl_display_roundtrip(display);
    usleep(50 * 1000);
    zwlr_virtual_pointer_v1_button(pointer, now_ms(), button, WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(pointer);
    wl_display_roundtrip(display);
  }

  zwlr_virtual_pointer_v1_destroy(pointer);
  wl_display_roundtrip(display);
  wl_display_disconnect(display);
  return 0;
}
