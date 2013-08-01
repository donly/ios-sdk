//
//  IRNewSignalScene2ViewController.m
//  IRKit
//
//  Created by Masakazu Ohtsuka on 2013/05/17.
//  Copyright (c) 2013年 KAYAC Inc. All rights reserved.
//

#import "IRNewSignalScene2ViewController.h"
#import "IRConst.h"
#import "IRViewCustomizer.h"

@interface IRNewSignalScene2ViewController ()

@end

@implementation IRNewSignalScene2ViewController

- (id) initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    LOG_CURRENT_METHOD;
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad {
    LOG_CURRENT_METHOD;
    [super viewDidLoad];

    self.title = @"Scene 2";
    self.navigationItem.hidesBackButton    = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self
                                                                                           action:@selector(doneButtonPressed:)];

    [IRViewCustomizer sharedInstance].viewDidLoad(self);
}

- (void) viewWillAppear:(BOOL)animated {
    LOG_CURRENT_METHOD;
    [super viewWillAppear:animated];

    [self editingChanged:nil];
}

- (void) viewWillDisappear:(BOOL)animated {
    LOG_CURRENT_METHOD;
    [super viewWillDisappear:animated];
}

- (void) processTextField {
    LOG( @"text: %@", _textField.text );

    if (! [self isTextValid]) {
        return;
    }

    [self.delegate scene2ViewController:self
                      didFinishWithInfo:@{
             IRViewControllerResultType: IRViewControllerResultTypeDone,
             IRViewControllerResultText: _textField.text,
           IRViewControllerResultSignal: _signal,
     }];
}


- (BOOL) isTextValid {
    if (! _textField.text) {
        return NO;
    }

    NSRegularExpression *regex = [NSRegularExpression
                                  regularExpressionWithPattern:@"^\s*$"
                                  options:nil
                                  error:nil];
    NSUInteger matches = [regex numberOfMatchesInString:_textField.text
                                                options:nil
                                                  range:NSMakeRange(0,_textField.text.length)];

    if (matches > 0) {
        // empty or whitespace only
        return NO;
    }
    return YES;
}

#pragma mark - UI events

- (void)didReceiveMemoryWarning
{
    LOG_CURRENT_METHOD;
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)doneButtonPressed:(id)selector
{
    LOG(@"text: %@", self.textField.text);
    [self processTextField];
}

- (IBAction)editingChanged:(id)sender {
    BOOL valid = [self isTextValid];
    self.navigationItem.rightBarButtonItem.enabled = valid;
    self.textField.textColor = valid ? [IRViewCustomizer activeFontColor] : [IRViewCustomizer inactiveFontColor];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField*)textField
{
    [self processTextField];
    return NO;
}

@end