# CustomKvo
实现一个简单的kvo
简单概述下KVO的实现：
当你观察一个对象时，一个新的类会动态被创建。这个类继承自该对象的原本的类，并重写了被观察属性的setter方法自然，重写的setter方法会负责在调用原setter方法之前最后把这个对象的isa指针（isa指针告诉运行系统这个对象的类是什么）指向这个新创建的子类，对象就是神奇的变成了新创建的子类的实例
参考文章：http://tech.glowing.com/cn/implement-kvo/
