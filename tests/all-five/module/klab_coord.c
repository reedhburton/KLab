#include <linux/version.h>
#include <linux/kernel.h>
#include <linux/module.h>

static int value = 7;

#if LINUX_VERSION_CODE < KERNEL_VERSION(2,4,0)
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,1,0)
MODULE_PARM(value, "i");
#endif
int init_module(void)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,1,0)
    printk(KERN_INFO "klab_coord: ready value=%d\n", value);
#endif
    return 0;
}
void cleanup_module(void)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,1,0)
    printk(KERN_INFO "klab_coord: stopped\n");
#endif
}
#else
#include <linux/init.h>
#include <linux/moduleparam.h>
module_param(value, int, 0644);
MODULE_PARM_DESC(value, "coordination value observed by guest processes");
static int __init klab_coord_init(void)
{
    printk(KERN_INFO "klab_coord: ready value=%d\n", value);
    return 0;
}
static void __exit klab_coord_exit(void)
{
    printk(KERN_INFO "klab_coord: stopped\n");
}
module_init(klab_coord_init);
module_exit(klab_coord_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("KLab cross-version process/module coordination gate");
#endif
