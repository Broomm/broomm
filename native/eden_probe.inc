// Pinned Eden's CheckEnvVars exits immediately after a Vulkan loader probe.
// It never initializes profiles, game storage or SDL. The real parent keeps
// its writer lock throughout fork/exec, waitpid and the remainder of its life.
static bool eden_vulkan_probe(void) {
    const char *value=getenv("YUZU_DO_STARTUP_CHECKS");
    return getenv("BROOMM_EDEN")&&value&&!strcmp(value,"ON");
}
