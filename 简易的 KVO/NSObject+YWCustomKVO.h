//
//  NSObject+YWCustomKVO.h
//  简易的 KVO
//
//  Created by changcai on 17/4/27.
//  Copyright © 2017年 changcai. All rights reserved.
//

/*
 简单概述下 KVO 的实现：
    当你观察一个对象时，一个新的类会动态被创建。这个类继承自该对象的原本的类，并重写了被观察属性的 setter 方法。自然，重写的 setter 方法会负责在调用原 setter 方法之前和之后，通知所有观察对象值的更改。最后把这个对象的 isa 指针 ( isa 指针告诉 Runtime 系统这个对象的类是什么 ) 指向这个新创建的子类，对象就神奇的变成了新创建的子类的实例。
 */

#import <Foundation/Foundation.h>

typedef void(^YWObservingBlock) (id observedObject, NSString *observedKey, id oldValue, id newValue);
@interface NSObject (YWCustomKVO)

/*添加一个观察者 */
- (void)YW_addObserver:(NSObject *)observer  forKey:(NSString *)key withBlock:(YWObservingBlock)block;
/*移除一个观察者 */
- (void) YW_removeObserver:(NSObject *)observer forKey:(NSString *)key;

@end
