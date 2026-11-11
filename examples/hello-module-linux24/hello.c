#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>

static int __init klab_hello_init(void)
{
    printk(KERN_INFO "klab_linux24_hello: loaded\n");
    return 0;
}

static void __exit klab_hello_exit(void)
{
    printk(KERN_INFO "klab_linux24_hello: unloaded\n");
}

module_init(klab_hello_init);
module_exit(klab_hello_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("KLab Linux 2.4 compatibility probe");
