#ifndef BROOMM_FILE_ICON_H
#define BROOMM_FILE_ICON_H
#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <cstring>

// Existing GTK/GIO interop only. File-manager metadata is optional; the Dart
// launcher installation owns destinations, persistence and user feedback.
namespace broomm_file_icon {
struct Request {
  FlMethodCall* call;
  GFile* file;
  GFileInfo* info;
  GCancellable* cancel;
  gchar* uri;
  guint timer=0;
};
inline void finish(Request* request,bool applied) {
  if(request->timer)g_source_remove(request->timer);
  g_autoptr(FlValue) value=fl_value_new_bool(applied);
  fl_method_call_respond_success(request->call,value,nullptr);
  g_object_unref(request->call);g_object_unref(request->file);
  g_object_unref(request->info);g_object_unref(request->cancel);
  g_free(request->uri);delete request;
}
inline void apply(FlMethodCall* call) {
  g_autofree gchar* executable=g_file_read_link("/proc/self/exe",nullptr);
  g_autofree gchar* parent=executable?g_path_get_dirname(executable):nullptr;
  g_autofree gchar* icon=parent?g_build_filename(parent,"data","broomm.png",nullptr):nullptr;
  if(!icon||!g_file_test(icon,G_FILE_TEST_IS_REGULAR)) {
    g_autoptr(FlValue) value=fl_value_new_bool(false);
    fl_method_call_respond_success(call,value,nullptr);return;
  }
  auto* request=new Request{FL_METHOD_CALL(g_object_ref(call)),g_file_new_for_path(executable),
    g_file_info_new(),g_cancellable_new(),g_filename_to_uri(icon,nullptr,nullptr)};
  if(!request->uri){finish(request,false);return;}
  g_file_info_set_attribute_string(request->info,"metadata::custom-icon",request->uri);
  request->timer=g_timeout_add_seconds(5,+[](gpointer data)->gboolean {
    auto* pending=static_cast<Request*>(data);pending->timer=0;
    g_cancellable_cancel(pending->cancel);return G_SOURCE_REMOVE;
  },request);
  g_file_set_attributes_async(request->file,request->info,G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS,
    G_PRIORITY_DEFAULT,request->cancel,+[](GObject* source,GAsyncResult* result,gpointer data){
      auto* pending=static_cast<Request*>(data);
      g_autoptr(GError) error=nullptr;g_autoptr(GFileInfo) info=nullptr;
      if(!g_file_set_attributes_finish(G_FILE(source),result,&info,&error)) {
        finish(pending,false);return;
      }
      g_file_query_info_async(pending->file,"metadata::custom-icon",G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS,
        G_PRIORITY_DEFAULT,pending->cancel,+[](GObject* file,GAsyncResult* queried,gpointer context){
          auto* item=static_cast<Request*>(context);
          g_autoptr(GError) problem=nullptr;
          g_autoptr(GFileInfo) observed=g_file_query_info_finish(G_FILE(file),queried,&problem);
          const char* uri=observed?g_file_info_get_attribute_string(observed,"metadata::custom-icon"):nullptr;
          finish(item,uri&&!strcmp(uri,item->uri));
        },pending);
    },request);
}
}
#endif
