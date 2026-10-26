import 'dart:io';

void main() {
  final s =
      '${Directory.current.path}/experiments/injection/sessions/retroarch';
  File('$s/retroarch.cfg').writeAsStringSync('''
config_save_on_exit = "false"
video_driver = "glcore"
video_fullscreen = "false"
video_windowed_fullscreen = "false"
video_window_width = "960"
video_window_height = "720"
audio_driver = "null"
input_driver = "sdl3"
input_joypad_driver = "sdl3"
input_autodetect_enable = "false"
input_player1_joypad_index = "0"
input_player1_a_btn = "0"
input_player1_b_btn = "1"
input_player1_start_btn = "6"
input_player1_select_btn = "4"
input_pause_nonactive = "false"
pause_nonactive = "false"
menu_show_start_screen = "false"
network_cmd_enable = "true"
network_cmd_port = "55355"
stdin_cmd_enable = "false"
savefile_directory = "$s/saves"
savestate_directory = "$s/states"
system_directory = "$s/system"
screenshot_directory = "$s/screenshots"
cache_directory = "$s/cache"
log_to_file = "false"
rgui_config_directory = "$s/config"
core_options_path = "$s/config/core-options.cfg"
playlist_directory = "$s/config/playlists"
runtime_log_directory = "$s/config/runtime"
input_remapping_directory = "$s/config/remaps"
''');
}
