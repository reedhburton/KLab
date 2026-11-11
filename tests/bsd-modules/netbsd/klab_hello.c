#include <sys/cdefs.h>
__KERNEL_RCSID(0, "$NetBSD$");

#include <sys/param.h>
#include <sys/module.h>

MODULE(MODULE_CLASS_MISC, klab_hello, NULL);

static int
klab_hello_modcmd(modcmd_t cmd, void *arg __unused)
{
        switch (cmd) {
        case MODULE_CMD_INIT:
                printf("KLAB_NETBSD_MODULE_LOADED\n");
                break;
        case MODULE_CMD_FINI:
                printf("KLAB_NETBSD_MODULE_UNLOADED\n");
                break;
        default:
                return ENOTTY;
        }
        return 0;
}
