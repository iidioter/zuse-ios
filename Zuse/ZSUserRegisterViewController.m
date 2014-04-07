//
//  ZSUserRegisterViewController.m
//  Zuse
//
//  Created by Sarah Hong on 3/11/14.
//  Copyright (c) 2014 Michael Hogenson. All rights reserved.
//

#import "ZSUserRegisterViewController.h"
#import "ZSZuseHubJSONClient.h"
#import "ZSZuseHubViewController.h"

@interface ZSUserRegisterViewController()

@property (strong, nonatomic) ZSZuseHubJSONClient *jsonClientManager;
@property (assign, nonatomic) BOOL didLogIn;
@property (strong, nonatomic) ZSZuseHubViewController *hubController;

@end

@implementation ZSUserRegisterViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.didLogIn = NO;
    self.jsonClientManager = [ZSZuseHubJSONClient sharedClient];
    
}
- (IBAction)backTapped:(id)sender {
    self.didFinish(self.didLogIn);
}
- (IBAction)registerTapped:(id)sender {
    if(self.usernameTextField.text.length != 0 &&
       self.passwordTextField.text.length != 0 &&
       self.emailTextField.text.length != 0)
    {
        NSDictionary *loginInfo = @{
                                     @"username": self.usernameTextField.text,
                                     @"email": self.emailTextField.text,
                                     @"password": self.passwordTextField.text
                                 };
        [self.jsonClientManager registerUser:loginInfo completion:^(NSDictionary *response) {
            if(response)
            {
                self.jsonClientManager.token = response[@"token"];
                [self.jsonClientManager setAuthHeader:self.jsonClientManager.token];
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setObject:self.jsonClientManager.token forKey:@"token"];
                [defaults synchronize];
                self.didLogIn = YES;
                self.errorMsgLabel.text = @"";
                [self close];
            }
            else{
                self.errorMsgLabel.text = @"Username taken or email invalid";
                [self close];
            }
        }];
    }
}

/**
 * Closes the navigation controller so that it can return to the main menu.
 */
- (void)close
{
    self.didFinish(self.didLogIn);
}

- (IBAction)outerViewTapped:(id)sender {
    [self.usernameTextField resignFirstResponder];
    [self.passwordTextField resignFirstResponder];
    [self.emailTextField resignFirstResponder];
}

@end