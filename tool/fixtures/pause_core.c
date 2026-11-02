// Original synthetic libretro fixture. Exercises the real frontend's pause and
// controller lifecycle, without downloading a game or shipping another core.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
struct system_info { const char *name,*version,*extensions; bool fullpath,extract; };
struct geometry { unsigned width,height,max_width,max_height; float aspect; };
struct timing { double fps,rate; };
struct av_info { struct geometry geometry; struct timing timing; };
static bool (*environment)(unsigned,void *);
static void (*video)(const void *,unsigned,unsigned,size_t),(*poll)(void);
static size_t (*audio)(const int16_t *,size_t);
static uint16_t pixels[16*16];
void retro_set_environment(bool (*f)(unsigned,void *)){environment=f;}
void retro_set_video_refresh(void (*f)(const void *,unsigned,unsigned,size_t)){video=f;}
void retro_set_audio_sample(void (*f)(int16_t,int16_t)){(void)f;}
void retro_set_audio_sample_batch(size_t (*f)(const int16_t *,size_t)){audio=f;}
void retro_set_input_poll(void (*f)(void)){poll=f;}
void retro_set_input_state(int16_t (*f)(unsigned,unsigned,unsigned,unsigned)){(void)f;}
void retro_init(void){int format=0;environment(10,&format);}
void retro_deinit(void){}
unsigned retro_api_version(void){return 1;}
void retro_get_system_info(struct system_info *i){*i=(struct system_info){"Broomm pause fixture","1","bin",false,false};}
void retro_get_system_av_info(struct av_info *i){*i=(struct av_info){{16,16,16,16,1},{60,48000}};}
void retro_set_controller_port_device(unsigned port,unsigned device){(void)port;(void)device;}
void retro_reset(void){}
void retro_run(void){static int16_t silence[1600];poll();video(pixels,16,16,32);audio(silence,800);}
size_t retro_serialize_size(void){return 0;}
bool retro_serialize(void *p,size_t n){(void)p;(void)n;return false;}
bool retro_unserialize(const void *p,size_t n){(void)p;(void)n;return false;}
void retro_cheat_reset(void){}
void retro_cheat_set(unsigned i,bool on,const char *s){(void)i;(void)on;(void)s;}
bool retro_load_game(const void *info){(void)info;return true;}
bool retro_load_game_special(unsigned type,const void *info,size_t count){(void)type;(void)info;(void)count;return false;}
void retro_unload_game(void){}
unsigned retro_get_region(void){return 0;}
void *retro_get_memory_data(unsigned id){(void)id;return NULL;}
size_t retro_get_memory_size(unsigned id){(void)id;return 0;}
