#include <sys/param.h>
#include <sys/kernel.h>
#include <sys/module.h>
#include <sys/systm.h>

static int
klab_hello_event(module_t module, int event, void *arg)
{
        switch (event) {
        case MOD_LOAD:
                kprintf("KLAB_DRAGONFLY_MODULE_LOADED\n");
                return 0;
        case MOD_UNLOAD:
                kprintf("KLAB_DRAGONFLY_MODULE_UNLOADED\n");
                return 0;
        default:
                return EOPNOTSUPP;
        }
}

static moduledata_t klab_hello_mod = {
        "klab_hello",
        klab_hello_event,
        NULL
};

DECLARE_MODULE(klab_hello, klab_hello_mod, SI_SUB_DRIVERS, SI_ORDER_MIDDLE);
