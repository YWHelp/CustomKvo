//
//  ViewController.m
//  简易的 KVO
//
//  Created by changcai on 17/4/27.
//  Copyright © 2017年 changcai. All rights reserved.
//

#import "ViewController.h"
#import "NSObject+YWCustomKVO.h"
//#import "NSObject+KVO.h"
@interface Person : NSObject
/**  */
@property (nonatomic, strong) NSNumber *age;//如果将age用基本数据类型申明，程序监听崩溃

@end

@implementation Person


@end

@interface ViewController ()
/**   */
@property (nonatomic, strong) Person *person;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.person = [[Person alloc]init];
    [self.person YW_addObserver:self forKey:NSStringFromSelector(@selector(age)) withBlock:^(id observedObject, NSString *observedKey, id oldValue, id newValue) {
        NSLog(@"-----新：%@---旧： %@--",newValue, oldValue);
        
    }];
    self.person.age = @18;
}


@end
