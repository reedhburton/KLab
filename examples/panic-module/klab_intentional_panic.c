#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>

static int __init klab_intentional_panic_init(void)
{
    panic("KLab intentional panic validation");
    return 0;
}

static void __exit klab_intentional_panic_exit(void) {}
module_init(klab_intentional_panic_init);
module_exit(klab_intentional_panic_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("KLab destructive crash-log validation module");
