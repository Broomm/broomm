// These are native configuration locations, not general filename filters.
// In particular, saves may themselves contain INI/JSON files inside a NAND or
// console savedata directory; those trees are never searched or removed here.
List<String> emulatorSettingsPaths(String id) => [
  'cache',
  'cache-intel',
  'home/Library/Preferences',
  ...switch (id) {
    'retroarch' => ['retroarch.cfg', 'config'],
    'dolphin' => ['user/Config'],
    'rpcs3' => [
      'portable/config.yml',
      'portable/config_input.yml',
      'portable/GuiConfigs',
      'portable/input_configs',
      'portable/custom_configs',
    ],
    'azahar' => ['home/Library/Application Support/Azahar/config'],
    'ryubing' || 'astris' => ['user/Config.json'],
    'eden' => ['config/eden'],
    'melonds' => [
      'launcher/portable/melonDS.toml',
      'launcher/portable/melonDS.ini',
      'user/melonDS.toml',
      'user/melonDS.ini',
    ],
    'duckstation' => [
      'home/Library/Application Support/DuckStation/settings.ini',
      'home/Library/Application Support/DuckStation/inputprofiles',
    ],
    'ps2' => ['user/pcsx2/PCSX2/inis', 'user/armsx2/ARMSX2/inis'],
    'ppsspp' => ['user/PSP/SYSTEM/ppsspp.ini', 'user/PSP/SYSTEM/controls.ini'],
    _ => <String>[],
  },
];
