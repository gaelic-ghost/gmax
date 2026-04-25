#include "ghostty.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct GmaxGhosttyRuntime GmaxGhosttyRuntime;
typedef struct GmaxGhosttySurface GmaxGhosttySurface;

typedef void (*gmax_ghostty_event_cb)(
    void *userdata,
    int event,
    const char *primary,
    const char *secondary,
    int64_t number);

enum {
  GMAX_GHOSTTY_EVENT_READY = 1,
  GMAX_GHOSTTY_EVENT_TITLE = 2,
  GMAX_GHOSTTY_EVENT_PWD = 3,
  GMAX_GHOSTTY_EVENT_BELL = 4,
  GMAX_GHOSTTY_EVENT_NOTIFICATION = 5,
  GMAX_GHOSTTY_EVENT_CHILD_EXITED = 6,
  GMAX_GHOSTTY_EVENT_COMMAND_FINISHED = 7,
  GMAX_GHOSTTY_EVENT_CLOSE_REQUESTED = 8,
  GMAX_GHOSTTY_EVENT_ERROR = 9,
};

struct GmaxGhosttyRuntime {
  void *sparkle_handle;
  void *ghostty_handle;
  ghostty_app_t app;
  gmax_ghostty_event_cb event_cb;
  void *userdata;
  GmaxGhosttySurface *surfaces;

  int (*ghostty_init)(uintptr_t, char **);
  ghostty_config_t (*ghostty_config_new)(void);
  void (*ghostty_config_load_default_files)(ghostty_config_t);
  void (*ghostty_config_finalize)(ghostty_config_t);
  ghostty_app_t (*ghostty_app_new)(const ghostty_runtime_config_s *, ghostty_config_t);
  void (*ghostty_app_free)(ghostty_app_t);
  void (*ghostty_app_tick)(ghostty_app_t);
  ghostty_surface_config_s (*ghostty_surface_config_new)(void);
  ghostty_surface_t (*ghostty_surface_new)(ghostty_app_t, const ghostty_surface_config_s *);
  void (*ghostty_surface_free)(ghostty_surface_t);
  void (*ghostty_surface_refresh)(ghostty_surface_t);
  void (*ghostty_surface_draw)(ghostty_surface_t);
  void (*ghostty_surface_set_content_scale)(ghostty_surface_t, double, double);
  void (*ghostty_surface_set_focus)(ghostty_surface_t, bool);
  void (*ghostty_surface_set_size)(ghostty_surface_t, uint32_t, uint32_t);
  void (*ghostty_surface_text)(ghostty_surface_t, const char *, uintptr_t);
  void (*ghostty_surface_preedit)(ghostty_surface_t, const char *, uintptr_t);
  bool (*ghostty_surface_key)(ghostty_surface_t, ghostty_input_key_s);
  bool (*ghostty_surface_mouse_button)(
      ghostty_surface_t,
      ghostty_input_mouse_state_e,
      ghostty_input_mouse_button_e,
      ghostty_input_mods_e);
  void (*ghostty_surface_mouse_pos)(ghostty_surface_t, double, double, ghostty_input_mods_e);
  void (*ghostty_surface_mouse_scroll)(ghostty_surface_t, double, double, ghostty_input_scroll_mods_t);
};

struct GmaxGhosttySurface {
  GmaxGhosttyRuntime *runtime;
  ghostty_surface_t surface;
  gmax_ghostty_event_cb event_cb;
  void *userdata;
  GmaxGhosttySurface *next;
};

static GmaxGhosttyRuntime *g_active_runtime = NULL;

static void set_error(char *error, size_t error_len, const char *message) {
  if (error == NULL || error_len == 0) {
    return;
  }

  snprintf(error, error_len, "%s", message == NULL ? "Unknown Ghostty shim error." : message);
}

static void *load_symbol(void *handle, const char *name, char *error, size_t error_len) {
  void *symbol = dlsym(handle, name);
  if (symbol == NULL) {
    char message[512];
    snprintf(message, sizeof(message), "The Ghostty shim could not find the required symbol %s.", name);
    set_error(error, error_len, message);
  }
  return symbol;
}

static void *load_optional_symbol(void *handle, const char *name) {
  return dlsym(handle, name);
}

static GmaxGhosttySurface *find_surface(GmaxGhosttyRuntime *runtime, ghostty_surface_t surface) {
  for (GmaxGhosttySurface *candidate = runtime->surfaces; candidate != NULL; candidate = candidate->next) {
    if (candidate->surface == surface) {
      return candidate;
    }
  }
  return NULL;
}

static GmaxGhosttySurface *surface_from_target(GmaxGhosttyRuntime *runtime, ghostty_target_s target) {
  if (target.tag != GHOSTTY_TARGET_SURFACE) {
    return NULL;
  }
  return find_surface(runtime, target.target.surface);
}

static void emit_runtime_event(
    GmaxGhosttyRuntime *runtime,
    int event,
    const char *primary,
    const char *secondary,
    int64_t number) {
  if (runtime != NULL && runtime->event_cb != NULL) {
    runtime->event_cb(runtime->userdata, event, primary, secondary, number);
  }
}

static void emit_surface_event(
    GmaxGhosttySurface *surface,
    int event,
    const char *primary,
    const char *secondary,
    int64_t number) {
  if (surface != NULL && surface->event_cb != NULL) {
    surface->event_cb(surface->userdata, event, primary, secondary, number);
  } else if (surface != NULL) {
    emit_runtime_event(surface->runtime, event, primary, secondary, number);
  }
}

static void runtime_wakeup(void *userdata) {
  GmaxGhosttyRuntime *runtime = userdata;
  if (runtime == NULL || runtime->app == NULL) {
    return;
  }
  runtime->ghostty_app_tick(runtime->app);
}

static bool runtime_action(ghostty_app_t app, ghostty_target_s target, ghostty_action_s action) {
  (void)app;
  GmaxGhosttyRuntime *runtime = g_active_runtime;
  if (runtime == NULL) {
    return false;
  }

  GmaxGhosttySurface *surface = surface_from_target(runtime, target);
  switch (action.tag) {
    case GHOSTTY_ACTION_RENDER:
      if (surface != NULL && runtime->ghostty_surface_draw != NULL) {
        runtime->ghostty_surface_draw(surface->surface);
      }
      return true;

    case GHOSTTY_ACTION_SET_TITLE:
      emit_surface_event(surface, GMAX_GHOSTTY_EVENT_TITLE, action.action.set_title.title, NULL, 0);
      return true;

    case GHOSTTY_ACTION_PWD:
      emit_surface_event(surface, GMAX_GHOSTTY_EVENT_PWD, action.action.pwd.pwd, NULL, 0);
      return true;

    case GHOSTTY_ACTION_RING_BELL:
      emit_surface_event(surface, GMAX_GHOSTTY_EVENT_BELL, NULL, NULL, 0);
      return true;

    case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
      emit_surface_event(
          surface,
          GMAX_GHOSTTY_EVENT_NOTIFICATION,
          action.action.desktop_notification.title,
          action.action.desktop_notification.body,
          0);
      return true;

    case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
      emit_surface_event(
          surface,
          GMAX_GHOSTTY_EVENT_CHILD_EXITED,
          NULL,
          NULL,
          action.action.child_exited.exit_code);
      return true;

    case GHOSTTY_ACTION_COMMAND_FINISHED:
      emit_surface_event(
          surface,
          GMAX_GHOSTTY_EVENT_COMMAND_FINISHED,
          NULL,
          NULL,
          action.action.command_finished.exit_code);
      return true;

    case GHOSTTY_ACTION_CLOSE_WINDOW:
    case GHOSTTY_ACTION_CLOSE_TAB:
      emit_surface_event(surface, GMAX_GHOSTTY_EVENT_CLOSE_REQUESTED, NULL, NULL, 0);
      return true;

    default:
      return true;
  }
}

static bool runtime_read_clipboard(void *userdata, ghostty_clipboard_e clipboard, void *request) {
  (void)userdata;
  (void)clipboard;
  (void)request;
  return false;
}

static void runtime_confirm_read_clipboard(
    void *userdata,
    const char *text,
    void *request,
    ghostty_clipboard_request_e request_type) {
  (void)userdata;
  (void)text;
  (void)request;
  (void)request_type;
}

static void runtime_write_clipboard(
    void *userdata,
    ghostty_clipboard_e clipboard,
    const ghostty_clipboard_content_s *content,
    size_t count,
    bool confirm) {
  (void)userdata;
  (void)clipboard;
  (void)content;
  (void)count;
  (void)confirm;
}

static void runtime_close_surface(void *userdata, bool process_alive) {
  GmaxGhosttySurface *surface = userdata;
  emit_surface_event(
      surface,
      GMAX_GHOSTTY_EVENT_CLOSE_REQUESTED,
      NULL,
      NULL,
      process_alive ? 1 : 0);
}

int gmax_ghostty_runtime_create(
    const char *ghostty_path,
    const char *sparkle_path,
    gmax_ghostty_event_cb event_cb,
    void *userdata,
    GmaxGhosttyRuntime **runtime_out,
    char *error,
    size_t error_len) {
  if (runtime_out == NULL) {
    set_error(error, error_len, "The Ghostty shim runtime output pointer was null.");
    return 0;
  }
  *runtime_out = NULL;

  GmaxGhosttyRuntime *runtime = calloc(1, sizeof(GmaxGhosttyRuntime));
  if (runtime == NULL) {
    set_error(error, error_len, "The Ghostty shim could not allocate runtime storage.");
    return 0;
  }
  runtime->event_cb = event_cb;
  runtime->userdata = userdata;
  g_active_runtime = runtime;

  if (sparkle_path != NULL && strlen(sparkle_path) > 0) {
    runtime->sparkle_handle = dlopen(sparkle_path, RTLD_NOW | RTLD_GLOBAL);
  }

  runtime->ghostty_handle = dlopen(ghostty_path, RTLD_NOW | RTLD_GLOBAL);
  if (runtime->ghostty_handle == NULL) {
    set_error(error, error_len, dlerror());
    g_active_runtime = NULL;
    free(runtime);
    return 0;
  }

#define LOAD(name)                                                                                  \
  do {                                                                                              \
    runtime->name = load_symbol(runtime->ghostty_handle, #name, error, error_len);                   \
    if (runtime->name == NULL) {                                                                    \
      free(runtime);                                                                                \
      return 0;                                                                                     \
    }                                                                                               \
  } while (0)

  LOAD(ghostty_init);
  LOAD(ghostty_config_new);
  LOAD(ghostty_config_load_default_files);
  LOAD(ghostty_config_finalize);
  LOAD(ghostty_app_new);
  LOAD(ghostty_app_free);
  LOAD(ghostty_app_tick);
  LOAD(ghostty_surface_config_new);
  LOAD(ghostty_surface_new);
  LOAD(ghostty_surface_free);
  LOAD(ghostty_surface_set_content_scale);
  LOAD(ghostty_surface_set_focus);
  LOAD(ghostty_surface_set_size);
  LOAD(ghostty_surface_text);
  LOAD(ghostty_surface_preedit);
  LOAD(ghostty_surface_key);
  LOAD(ghostty_surface_mouse_button);
  LOAD(ghostty_surface_mouse_pos);
  LOAD(ghostty_surface_mouse_scroll);

#undef LOAD

  runtime->ghostty_surface_refresh = load_optional_symbol(runtime->ghostty_handle, "ghostty_surface_refresh");
  runtime->ghostty_surface_draw = load_optional_symbol(runtime->ghostty_handle, "ghostty_surface_draw");

  char *argv[] = {"gmax-ghostty-spike", NULL};
  int init_result = runtime->ghostty_init(1, argv);
  if (init_result != GHOSTTY_SUCCESS) {
    set_error(error, error_len, "ghostty_init failed while creating the gmax Ghostty spike runtime.");
    g_active_runtime = NULL;
    free(runtime);
    return 0;
  }

  ghostty_config_t config = runtime->ghostty_config_new();
  runtime->ghostty_config_load_default_files(config);
  runtime->ghostty_config_finalize(config);

  ghostty_runtime_config_s runtime_config = {
      .userdata = runtime,
      .supports_selection_clipboard = false,
      .wakeup_cb = runtime_wakeup,
      .action_cb = runtime_action,
      .read_clipboard_cb = runtime_read_clipboard,
      .confirm_read_clipboard_cb = runtime_confirm_read_clipboard,
      .write_clipboard_cb = runtime_write_clipboard,
      .close_surface_cb = runtime_close_surface,
  };
  runtime->app = runtime->ghostty_app_new(&runtime_config, config);

  if (runtime->app == NULL) {
    set_error(error, error_len, "ghostty_app_new returned null while creating the gmax Ghostty spike runtime.");
    g_active_runtime = NULL;
    free(runtime);
    return 0;
  }

  *runtime_out = runtime;
  emit_runtime_event(runtime, GMAX_GHOSTTY_EVENT_READY, "Ghostty runtime ready.", NULL, 0);
  return 1;
}

void gmax_ghostty_runtime_tick(GmaxGhosttyRuntime *runtime) {
  if (runtime == NULL || runtime->app == NULL) {
    return;
  }
  runtime->ghostty_app_tick(runtime->app);
}

void gmax_ghostty_runtime_destroy(GmaxGhosttyRuntime *runtime) {
  if (runtime == NULL) {
    return;
  }
  if (runtime->app != NULL) {
    runtime->ghostty_app_free(runtime->app);
  }
  if (g_active_runtime == runtime) {
    g_active_runtime = NULL;
  }
  free(runtime);
}

int gmax_ghostty_surface_create(
    GmaxGhosttyRuntime *runtime,
    void *nsview,
    const char *working_directory,
    const char *command,
    double scale_factor,
    float font_size,
    gmax_ghostty_event_cb event_cb,
    void *userdata,
    GmaxGhosttySurface **surface_out,
    char *error,
    size_t error_len) {
  if (surface_out == NULL) {
    set_error(error, error_len, "The Ghostty shim surface output pointer was null.");
    return 0;
  }
  *surface_out = NULL;

  if (runtime == NULL || runtime->app == NULL) {
    set_error(error, error_len, "The Ghostty shim runtime was not initialized before creating a surface.");
    return 0;
  }

  GmaxGhosttySurface *surface = calloc(1, sizeof(GmaxGhosttySurface));
  if (surface == NULL) {
    set_error(error, error_len, "The Ghostty shim could not allocate surface storage.");
    return 0;
  }
  surface->runtime = runtime;
  surface->event_cb = event_cb;
  surface->userdata = userdata;

  ghostty_surface_config_s config = runtime->ghostty_surface_config_new();
  config.platform_tag = GHOSTTY_PLATFORM_MACOS;
  config.platform.macos.nsview = nsview;
  config.userdata = surface;
  config.scale_factor = scale_factor;
  config.font_size = font_size;
  config.working_directory = working_directory;
  config.command = command;
  config.context = GHOSTTY_SURFACE_CONTEXT_SPLIT;

  surface->surface = runtime->ghostty_surface_new(runtime->app, &config);
  if (surface->surface == NULL) {
    set_error(error, error_len, "ghostty_surface_new returned null while creating a gmax Ghostty pane surface.");
    free(surface);
    return 0;
  }

  surface->next = runtime->surfaces;
  runtime->surfaces = surface;
  *surface_out = surface;
  if (runtime->ghostty_surface_refresh != NULL) {
    runtime->ghostty_surface_refresh(surface->surface);
  }
  return 1;
}

void gmax_ghostty_surface_destroy(GmaxGhosttySurface *surface) {
  if (surface == NULL) {
    return;
  }
  GmaxGhosttyRuntime *runtime = surface->runtime;
  if (runtime != NULL) {
    GmaxGhosttySurface **cursor = &runtime->surfaces;
    while (*cursor != NULL) {
      if (*cursor == surface) {
        *cursor = surface->next;
        break;
      }
      cursor = &(*cursor)->next;
    }
    if (surface->surface != NULL) {
      runtime->ghostty_surface_free(surface->surface);
    }
  }
  free(surface);
}

void gmax_ghostty_surface_set_size(GmaxGhosttySurface *surface, uint32_t width, uint32_t height) {
  if (surface == NULL || surface->surface == NULL) {
    return;
  }
  surface->runtime->ghostty_surface_set_size(surface->surface, width, height);
}

void gmax_ghostty_surface_set_scale(GmaxGhosttySurface *surface, double scale) {
  if (surface == NULL || surface->surface == NULL) {
    return;
  }
  surface->runtime->ghostty_surface_set_content_scale(surface->surface, scale, scale);
}

void gmax_ghostty_surface_set_focus(GmaxGhosttySurface *surface, bool focused) {
  if (surface == NULL || surface->surface == NULL) {
    return;
  }
  surface->runtime->ghostty_surface_set_focus(surface->surface, focused);
}

void gmax_ghostty_surface_text(GmaxGhosttySurface *surface, const char *text, uintptr_t len) {
  if (surface == NULL || surface->surface == NULL || text == NULL) {
    return;
  }
  surface->runtime->ghostty_surface_text(surface->surface, text, len);
}

void gmax_ghostty_surface_preedit(GmaxGhosttySurface *surface, const char *text, uintptr_t len) {
  if (surface == NULL || surface->surface == NULL) {
    return;
  }
  surface->runtime->ghostty_surface_preedit(surface->surface, text, len);
}

bool gmax_ghostty_surface_key(
    GmaxGhosttySurface *surface,
    int action,
    int mods,
    const char *text,
    uint32_t keycode,
    uint32_t unshifted_codepoint,
    bool composing) {
  if (surface == NULL || surface->surface == NULL) {
    return false;
  }

  ghostty_input_key_s input = {
      .action = action == 0 ? GHOSTTY_ACTION_RELEASE : (action == 2 ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS),
      .mods = mods,
      .consumed_mods = GHOSTTY_MODS_NONE,
      .keycode = keycode,
      .text = text,
      .unshifted_codepoint = unshifted_codepoint,
      .composing = composing,
  };
  return surface->runtime->ghostty_surface_key(surface->surface, input);
}

void gmax_ghostty_surface_mouse_position(GmaxGhosttySurface *surface, double x, double y) {
  if (surface == NULL || surface->surface == NULL) {
    return;
  }
  surface->runtime->ghostty_surface_mouse_pos(surface->surface, x, y, GHOSTTY_MODS_NONE);
}

void gmax_ghostty_surface_mouse_button(GmaxGhosttySurface *surface, int state, int button) {
  if (surface == NULL || surface->surface == NULL) {
    return;
  }
  surface->runtime->ghostty_surface_mouse_button(
      surface->surface,
      state == 0 ? GHOSTTY_MOUSE_RELEASE : GHOSTTY_MOUSE_PRESS,
      button == 1 ? GHOSTTY_MOUSE_RIGHT : GHOSTTY_MOUSE_LEFT,
      GHOSTTY_MODS_NONE);
}

void gmax_ghostty_surface_scroll(GmaxGhosttySurface *surface, double x, double y) {
  if (surface == NULL || surface->surface == NULL) {
    return;
  }
  surface->runtime->ghostty_surface_mouse_scroll(surface->surface, x, y, 0);
}

void gmax_ghostty_surface_refresh(GmaxGhosttySurface *surface) {
  if (surface == NULL || surface->surface == NULL) {
    return;
  }
  if (surface->runtime->ghostty_surface_refresh != NULL) {
    surface->runtime->ghostty_surface_refresh(surface->surface);
  }
}
