//
//  NSObject+YWCustomKVO.m
//  简易的 KVO
//
//  Created by changcai on 17/4/27.
//  Copyright © 2017年 changcai. All rights reserved.
//

#import "NSObject+YWCustomKVO.h"
#import <objc/message.h>


 NSString *const kYWKVOClassPrefix = @"YWKVOClassPrefix_";
 NSString *const kYWKVOAssociatedObservers = @"YWKVOAssociatedObservers";

#pragma mark - PGObservationInfo
@interface YWObservationInfo : NSObject

@property (nonatomic, weak) NSObject *observer;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) YWObservingBlock block;

@end

@implementation YWObservationInfo

- (instancetype)initWithObserver:(NSObject *)observer Key:(NSString *)key block:(YWObservingBlock)block
{
    self = [super init];
    if (self) {
        _observer = observer;
        _key = key;
        _block = block;
    }
    return self;
}

@end


#pragma mark - Debug Help Methods
static NSArray *ClassMethodNames(Class c)
{
    NSMutableArray *array = [NSMutableArray array];
    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(c, &methodCount);
    unsigned int i;
    for(i = 0; i < methodCount; i++) {
        [array addObject: NSStringFromSelector(method_getName(methodList[i]))];
    }
    free(methodList);
    return array;
}

static void PrintDescription(NSString *name, id obj)
{
    NSString *str = [NSString stringWithFormat:
                     @"%@: %@\n\tNSObject class %s\n\tRuntime class %s\n\timplements methods <%@>\n\n",
                     name,
                     obj,
                     class_getName([obj class]),
                     class_getName(object_getClass(obj)),
                     [ClassMethodNames(object_getClass(obj)) componentsJoinedByString:@", "]];
    printf("%s\n", [str UTF8String]);
}


static NSString * setterForGetter (NSString *getter){
    
    if (getter.length <= 0) {
        return nil;
    }
    // upper case the first letter
    NSString *firstLetter = [[getter substringToIndex:1] uppercaseString];
    NSString *remainingLetters = [getter substringFromIndex:1];
    
    // add 'set' at the begining and ':' at the end
    NSString *setter = [NSString stringWithFormat:@"set%@%@:", firstLetter, remainingLetters];
    return setter;
}

//setter方法
static NSString * getterForSetter(NSString *setter)
{
    
    if(setter.length <= 0 || ![setter hasPrefix:@"set"] || ![setter hasSuffix:@":"]){
        return nil;
    }
    // remove 'set' at the begining and ':' at the end
    NSRange range = NSMakeRange(3, setter.length - 4);
    NSString *key = [setter substringWithRange:range];
    // lower case the first letter
    NSString *firstLetter = [[key substringToIndex:1] lowercaseString];
    key = [key stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                       withString:firstLetter];
    return key;
}

//重写setter方法
static void kvo_setter(id self, SEL _cmd, id newValue)
{
    //获取方法名
    NSString *setterName = NSStringFromSelector(_cmd);
    NSString *getterName = getterForSetter(setterName);
    if(!getterName){
        
        @throw [NSException exceptionWithName: NSInvalidArgumentException reason: [NSString stringWithFormat: @"unrecognized selector sent to instance %p", self] userInfo: nil];
        return;
    }
    id oldValue = [self valueForKey:getterName];
    struct  objc_super superClass = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self))
    };
    [self willChangeValueForKey: getterName];
    void  (*objc_msgSendSuperCasted) (void *, SEL ,id) = (void *)objc_msgSendSuper;
    //调用父类的setter方法，实际上是原始类的setter方法
    objc_msgSendSuperCasted(&superClass, _cmd, newValue);
    [self didChangeValueForKey: getterName];
    //获取所有监听回调对象进行回调
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)(kYWKVOAssociatedObservers));
    for (YWObservationInfo *each in observers) {
        if ([each.key isEqualToString:getterName]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                each.block(self, getterName, oldValue, newValue);
            });
        }
    }
}

static Class kvo_class(id self, SEL _cmd)
{
    return class_getSuperclass(object_getClass(self));
}
@implementation NSObject (YWCustomKVO)

/*
 实现 YW_addObserver:forKey:withBlock: 方法：
 1、检查对象的类有没有相应的setter方法，如果没有，就抛出异常。
 2、检查对象isa指针，指向的类是不是一个KVO类，如果不是，新建一个类继承原来类的子类，并把isa指针指向这个新建的子类；
 3、检查对象的KVO类有没有重写过setter方法，如果没有，添加重写的setter方法；
 4、添加这个观察者；
*/
- (void)YW_addObserver:(NSObject *)observer forKey:(NSString *)key withBlock:(YWObservingBlock)block
{
    // Step 1
    //获取方法编号
    NSLog(@"---%@---", [NSObject fetchIvarList:[self class]]);
    SEL setterSelector = NSSelectorFromString(setterForGetter(key));
    //根据方法编号获取方法
    Method setterMethod = class_getInstanceMethod([self class], setterSelector);
    if(!setterMethod){
        //throw invalid argument exception
        NSString *reason = [NSString stringWithFormat:@"Object %@ does not have a setter for key %@", self, key];
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:reason
                                     userInfo:nil];
        return;
    }
    //获取对象isa指针
    Class observedClass = object_getClass(self);
    NSString *className = NSStringFromClass(observedClass);
    // Step 2
    //检查对象isa指针，指向的类是不是一个KVO类
    if(![className hasPrefix:kYWKVOClassPrefix]){
        //动态创建一个类，继承至原来类的子类
        observedClass = [self dynamicCreateKvoClassWithOriginalClassName:className];
        //并把isa指针指向这个新建的子类
        object_setClass(self, observedClass);
    }
    
    //Step 3
    //检查对象的KVO类有没有重写过setter方法
    if(![self hasSelector:setterSelector]){
        const char *types = method_getTypeEncoding(setterMethod);
        class_addMethod(observedClass, setterSelector, (IMP)kvo_setter, types);
    }
    // Step 4
    YWObservationInfo *info = [[YWObservationInfo alloc] initWithObserver:observer Key:key block:block];
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)(kYWKVOAssociatedObservers));
    if (!observers) {
        observers = [NSMutableArray array];
        objc_setAssociatedObject(self, (__bridge const void *)(kYWKVOAssociatedObservers), observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [observers addObject:info];
}

- (void) YW_removeObserver:(NSObject *)observer forKey:(NSString *)key
{
   //获取所有的观察者对象
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)(kYWKVOAssociatedObservers));
    YWObservationInfo *infoToRemove;
    for (YWObservationInfo* info in observers) {
        if (info.observer == observer && [info.key isEqual:key]) {
            infoToRemove = info;
            break;
        }
    }
    [observers removeObject:infoToRemove];
}

//动态创建一个类
- (Class)dynamicCreateKvoClassWithOriginalClassName:(NSString *)originalClazzName
{
    //拼接子类的类名
    NSString *kvoClassName = [kYWKVOClassPrefix stringByAppendingString:originalClazzName];
    //获取新的类
    Class newClassIsa = NSClassFromString(kvoClassName);
    //如果已经创建好了这个子类，直接返回
    if(newClassIsa){
        return newClassIsa;
    }
    //获取原有类的isa指针
    Class originalClassIsa = object_getClass(self);
    //为新建的类开辟空间
    Class kvoClass = objc_allocateClassPair(originalClassIsa, kvoClassName.UTF8String, 0);
    //获取原始类的实例方法
    Method classMethod = class_getInstanceMethod(originalClassIsa, @selector(class));
    const char *types = method_getTypeEncoding(classMethod);
    class_addMethod(kvoClass, @selector(class), (IMP)kvo_class, types);
    objc_registerClassPair(kvoClass);
    return kvoClass;
}

//检查对象的KVO类有没有重写过setter方法
- (BOOL)hasSelector:(SEL)selector
{
    Class calssIsa = object_getClass(self);
    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(calssIsa, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        SEL thisSelector = method_getName(methodList[i]);
        if (thisSelector == selector) {
            free(methodList);
            return YES;
        }
    }
    free(methodList);
    return NO;
}

/*
 获取成员变量
 */
+ (NSArray *)fetchIvarList:(Class)class
{
    unsigned int count = 0;
    Ivar *ivarList = class_copyIvarList(class,&count);
    NSMutableArray *mutableList = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        NSMutableDictionary *mutableDict = [NSMutableDictionary dictionaryWithCapacity:2];
        const char *ivarName = ivar_getName(ivarList[i]);
        const char *ivarType = ivar_getTypeEncoding(ivarList[i]);
        mutableDict[@"ivarName"] = [NSString stringWithUTF8String:ivarName];
        mutableDict[@"ivarType"] = [NSString stringWithUTF8String:ivarType];
        [mutableList addObject:mutableDict];
    }
    free(ivarList);
    return [NSArray arrayWithArray:mutableList];
    
}
@end
