// Official 1.1 ARM64 only, additionally executable-hash pinned by Dart. Use
// the same frontend touch fields as ScreenPanel's native mouse handlers.
static bool melonds_frontend_layout(void) {
    static int checked;
    if(!checked) {
        const uint32_t *close_event=symbol("_ZN10MainWindow10closeEventEP11QCloseEvent");
        const uint32_t *press=symbol("_ZN11ScreenPanel15mousePressEventEP11QMouseEvent");
        const uint32_t *release=symbol("_ZN11ScreenPanel17mouseReleaseEventEP11QMouseEvent");
        checked=close_event&&press&&release&&
            close_event[11]==0xf9404400&&close_event[13]==0xb9407e88&&
            press[40]==0xf9401e69&&press[41]==0x52847c8a&&
            press[44]==0x7900052a&&press[45]==0x7900092b&&press[46]==0x39000128&&
            release[12]==0x52847c89&&release[14]==0x14000002 ? 1 : -1;
    }
    return checked==1;
}
static bool melonds_primary(void *window) {
    return melonds_frontend_layout()&&*(int *)((char *)window+0x7c)==0;
}
static _Atomic uint32_t melonds_touch_readback;
static void melonds_remote_touch(bool pressed,int x,int y) {
    void *thread=melonds_thread();
    if(!thread||!melonds_frontend_layout())return;
    char *instance=*(char **)((char *)qt_main+0x88);
    if(!instance||*(void **)(instance+0x10)!=thread)return;
    if(!__atomic_load_n((uint8_t *)thread+0x38,__ATOMIC_ACQUIRE))return;
    if(pressed) {
        *(uint16_t *)(instance+0x23e6)=(uint16_t)x;
        *(uint16_t *)(instance+0x23e8)=(uint16_t)y;
    }
    *(uint8_t *)(instance+0x23e4)=pressed;
    atomic_store(&melonds_touch_readback,(pressed?1u<<16:0)|(unsigned)x|((unsigned)y<<8));
}
