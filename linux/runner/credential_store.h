#ifndef BROOMM_CREDENTIAL_STORE_H_
#define BROOMM_CREDENTIAL_STORE_H_
#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <cstring>
#include <stdexcept>
#include <string>

// Uses GIO already linked by the GTK runner. No libsecret package/helper is
// required. An unlocked Secret Service provider on the session bus is required.
namespace broomm_credentials {
struct Job { FlMethodCall* call; std::string method, key, value; GSource* timeout; };
struct SecretService {
  GDBusConnection* bus;
  GCancellable* cancel;
  std::string session;
  explicit SecretService(GCancellable* c) : bus(g_bus_get_sync(G_BUS_TYPE_SESSION, c, nullptr)), cancel(c) {
    if (!bus) throw std::runtime_error("Session bus unavailable");
  }
  ~SecretService() {
    if (!session.empty()) {
      GVariant* result = g_dbus_connection_call_sync(bus, "org.freedesktop.secrets", session.c_str(),
          "org.freedesktop.Secret.Session", "Close", nullptr, nullptr, G_DBUS_CALL_FLAGS_NONE, 500, nullptr, nullptr);
      if (result) g_variant_unref(result);
    }
    g_object_unref(bus);
  }
  GVariant* call(const char* path, const char* interface, const char* method, GVariant* args, const char* type) {
    GVariant* result = g_dbus_connection_call_sync(bus, "org.freedesktop.secrets", path, interface, method, args,
        type ? G_VARIANT_TYPE(type) : nullptr, G_DBUS_CALL_FLAGS_NONE, 1500, cancel, nullptr);
    if (!result) throw std::runtime_error("Secure store unavailable or locked");
    return result;
  }
  GVariant* attributes(const std::string& key) {
    GVariantBuilder attrs; g_variant_builder_init(&attrs, G_VARIANT_TYPE("a{ss}"));
    g_variant_builder_add(&attrs, "{ss}", "application", "app.broomm.romm.v1");
    g_variant_builder_add(&attrs, "{ss}", "profile", key.c_str());
    return g_variant_builder_end(&attrs);
  }
  std::string run(const Job& job, bool& present) {
    const char* service = "org.freedesktop.Secret.Service";
    const char* root = "/org/freedesktop/secrets";
    g_autoptr(GVariant) found = call(root, service, "SearchItems", g_variant_new("(@a{ss})", attributes(job.key)), "(aoao)");
    g_autoptr(GVariant) unlocked = g_variant_get_child_value(found, 0);
    g_autoptr(GVariant) locked = g_variant_get_child_value(found, 1);
    if (g_variant_n_children(locked) || g_variant_n_children(unlocked) > 1) throw std::runtime_error("Locked or ambiguous credential");
    std::string item;
    if (g_variant_n_children(unlocked)) {
      g_autoptr(GVariant) path = g_variant_get_child_value(unlocked, 0);
      item = g_variant_get_string(path, nullptr);
    }
    if (job.method == "delete") {
      if (!item.empty()) {
        g_autoptr(GVariant) result = call(item.c_str(), "org.freedesktop.Secret.Item", "Delete", nullptr, "(o)");
        g_autoptr(GVariant) prompt = g_variant_get_child_value(result, 0);
        if (std::strcmp(g_variant_get_string(prompt, nullptr), "/")) throw std::runtime_error("Unlock required");
      }
      return "";
    }
    if (job.method == "read" && item.empty()) return "";
    g_autoptr(GVariant) opened = call(root, service, "OpenSession", g_variant_new("(sv)", "plain", g_variant_new_string("")), "(vo)");
    g_autoptr(GVariant) path = g_variant_get_child_value(opened, 1);
    session = g_variant_get_string(path, nullptr);
    if (session == "/") throw std::runtime_error("No secret session");
    if (job.method == "read") {
      g_autoptr(GVariant) result = call(item.c_str(), "org.freedesktop.Secret.Item", "GetSecret", g_variant_new("(o)", session.c_str()), "((oayays))");
      g_autoptr(GVariant) secret = g_variant_get_child_value(result, 0);
      g_autoptr(GVariant) returned_session = g_variant_get_child_value(secret, 0);
      g_autoptr(GVariant) parameters = g_variant_get_child_value(secret, 1);
      g_autoptr(GVariant) value = g_variant_get_child_value(secret, 2);
      gsize size = 0;
      const auto* bytes = static_cast<const char*>(g_variant_get_fixed_array(value, &size, 1));
      if (session != g_variant_get_string(returned_session, nullptr) || g_variant_n_children(parameters) || size > 32768 ||
          (size && (!bytes || std::memchr(bytes, 0, size) || !g_utf8_validate(bytes, static_cast<gssize>(size), nullptr)))) throw std::runtime_error("Invalid secret");
      present = true;
      return size ? std::string(bytes, size) : "";
    }
    g_autoptr(GVariant) secret = g_variant_ref_sink(g_variant_new("(o@ay@ays)", session.c_str(),
        g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, nullptr, 0, 1),
        g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, job.value.data(), job.value.size(), 1), "text/plain; charset=utf8"));
    if (!item.empty()) {
      g_autoptr(GVariant) result = call(item.c_str(), "org.freedesktop.Secret.Item", "SetSecret", g_variant_new("(@(oayays))", g_variant_ref(secret)), "()");
      return "";
    }
    g_autoptr(GVariant) alias = call(root, service, "ReadAlias", g_variant_new("(s)", "default"), "(o)");
    g_autoptr(GVariant) collection = g_variant_get_child_value(alias, 0);
    const char* location = g_variant_get_string(collection, nullptr);
    if (!std::strcmp(location, "/")) throw std::runtime_error("No default keyring");
    GVariantBuilder props; g_variant_builder_init(&props, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&props, "{sv}", "org.freedesktop.Secret.Item.Label", g_variant_new_string("Broomm RomM sign-in"));
    g_variant_builder_add(&props, "{sv}", "org.freedesktop.Secret.Item.Attributes", attributes(job.key));
    g_autoptr(GVariant) result = call(location, "org.freedesktop.Secret.Collection", "CreateItem",
        g_variant_new("(@a{sv}@(oayays)b)", g_variant_builder_end(&props), g_variant_ref(secret), TRUE), "(oo)");
    g_autoptr(GVariant) prompt = g_variant_get_child_value(result, 1);
    if (std::strcmp(g_variant_get_string(prompt, nullptr), "/")) throw std::runtime_error("Unlock required");
    return "";
  }
};

inline void register_store(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(messenger, "app.broomm/credentials", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, [](FlMethodChannel*, FlMethodCall* call, gpointer) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* key_value = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, "key") : nullptr;
    FlValue* value = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, "value") : nullptr;
    const char* key = key_value && fl_value_get_type(key_value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(key_value) : "";
    const char* method = fl_method_call_get_name(call);
    const char* text = value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(value) : "";
    const char* identity = !std::strncmp(key, "sgdb-", 5) ? key + 5 : key;
    if (std::strlen(identity) != 32 || std::strspn(identity, "0123456789abcdef") != 32 ||
        (std::strcmp(method, "read") && std::strcmp(method, "write") && std::strcmp(method, "delete")) ||
        (!std::strcmp(method, "write") && (!value || fl_value_get_type(value) != FL_VALUE_TYPE_STRING || std::strlen(text) > 32768))) {
      fl_method_call_respond_error(call, "secure_store", "Invalid secure-store request", nullptr, nullptr); return;
    }
    auto* job = new Job{FL_METHOD_CALL(g_object_ref(call)), method, key, text, nullptr};
    g_autoptr(GCancellable) cancel = g_cancellable_new();
    job->timeout = g_timeout_source_new(9000);
    g_source_set_callback(job->timeout, [](gpointer value) -> gboolean {
      g_cancellable_cancel(G_CANCELLABLE(value)); return G_SOURCE_REMOVE;
    }, g_object_ref(cancel), g_object_unref);
    g_source_attach(job->timeout, nullptr);
    GTask* task = g_task_new(nullptr, cancel, [](GObject*, GAsyncResult* result, gpointer) {
      auto* task = G_TASK(result);
      auto* job = static_cast<Job*>(g_task_get_task_data(task));
      g_source_destroy(job->timeout);
      g_source_unref(job->timeout);
      g_autoptr(GError) error = nullptr;
      g_autofree gchar* value = static_cast<gchar*>(g_task_propagate_pointer(task, &error));
      if (error) fl_method_call_respond_error(job->call, "secure_store", "Secure sign-in storage is locked or unavailable.", nullptr, nullptr);
      else {
        g_autoptr(FlValue) response = value ? fl_value_new_string(value) : nullptr;
        fl_method_call_respond_success(job->call, response, nullptr);
      }
    }, nullptr);
    g_task_set_task_data(task, job, [](gpointer data) {
      auto* job = static_cast<Job*>(data); g_object_unref(job->call); delete job;
    });
    g_task_run_in_thread(task, [](GTask* task, gpointer, gpointer data, GCancellable* cancel) {
      try {
        bool present = false;
        SecretService service(cancel);
        const std::string value = service.run(*static_cast<Job*>(data), present);
        g_task_return_pointer(task, present ? g_strdup(value.c_str()) : nullptr, g_free);
      } catch (...) { g_task_return_new_error(task, G_IO_ERROR, G_IO_ERROR_FAILED, "Secure store unavailable"); }
    });
    g_object_unref(task);
  }, nullptr, nullptr);
}
}  // namespace broomm_credentials
#endif
