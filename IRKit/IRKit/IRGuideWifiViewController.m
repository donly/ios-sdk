//
//  IRWifiAdhocViewController.m
//  IRKit
//
//  Created by Masakazu Ohtsuka on 2014/01/05.
//
//
// successful behaviour:
// viewDidLoad
// wait til POST /1/door succeeds
// launch settings app, connect to IRKit wi-fi, back to our app
// DidBecomeActive
// show HUD
// wait til GET / against 192.168.1.1 succeeds
// wait til POST /1/door succeeds
// POST /wifi
// hide HUD
// alert("connect to home wi-fi")
// launch settings app, connect to home wi-fi, back to our app
// DidBecomeActive
// show HUD
// wait til POST /1/door succeeds
// hide HUD
// finish


#import "Log.h"
#import "IRGuideWifiViewController.h"
#import "IRHTTPClient.h"
#import "IRHelper.h"
#import "IRKit.h"
#import "IRConst.h"
#import "IRProgressView.h"
#import "IRFAQViewController.h"

const NSTimeInterval kIntervalToHideHUD  = 0.3;
const NSTimeInterval kWiFiConnectTimeout = 15.0;
const NSInteger kAlertTag401             = 401;
const NSInteger kAlertTagTimeout         = 499;

@interface IRGuideWifiViewController ()

@property (nonatomic) id becomeActiveObserver;
@property (nonatomic) id willResignActiveObserver;
@property (nonatomic) IRHTTPClient *doorWaiter;
@property (nonatomic) BOOL postWifiSucceeded;
@property (nonatomic) NSDate *becameActiveAt;
@property (nonatomic) NSTimer *doorWaiterLimitTimer;

@end

@implementation IRGuideWifiViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName: nibNameOrNil bundle: nibBundleOrNil];
    if (self) {
        __weak typeof(self) _self = self;
        _becomeActiveObserver     = [[NSNotificationCenter defaultCenter] addObserverForName: UIApplicationDidBecomeActiveNotification
                                                                                      object: nil
                                                                                       queue: [NSOperationQueue mainQueue]
                                                                                  usingBlock:^(NSNotification *note) {
            LOG(@"became active");
            _self.becameActiveAt = [NSDate date];

            // show HUD (hide before show to avoid double)
            [IRProgressView hideHUDForView: _self.view afterDelay: 0];
            [IRProgressView showHUDAddedTo: _self.view];

            if (!_self.postWifiSucceeded) {
                [_self checkAndPostWifiCredentialsIfAdhoc];
            }
            else {
                if (_self.doorWaiterLimitTimer) {
                    [_self.doorWaiterLimitTimer invalidate];
                }
                _self.doorWaiterLimitTimer = [NSTimer scheduledTimerWithTimeInterval: 30
                                                                              target: _self
                                                                            selector: @selector(doorWaiterTimeout:)
                                                                            userInfo: NULL
                                                                             repeats: NO];
            }
            [_self startWaitingForDoor];
        }];
        _willResignActiveObserver = [[NSNotificationCenter defaultCenter] addObserverForName: UIApplicationWillResignActiveNotification
                                                                                      object: nil
                                                                                       queue: [NSOperationQueue mainQueue]
                                                                                  usingBlock:^(NSNotification *note) {
            LOG(@"will resign active");
            [IRHTTPClient cancelLocalRequests];
        }];
    }
    return self;
}

- (void)dealloc {
    LOG_CURRENT_METHOD;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = IRLocalizedString(@"Connect to IRKit Wi-Fi", @"title of IRGuideWifiViewController");
    [IRViewCustomizer sharedInstance].viewDidLoad(self);

    _postWifiSucceeded = NO;
}

- (void)viewWillDisappear:(BOOL)animated {
    LOG_CURRENT_METHOD;

    [_doorWaiter cancel];
    _doorWaiter = nil;

    [_doorWaiterLimitTimer invalidate];
    _doorWaiterLimitTimer = nil;

    [IRHTTPClient cancelLocalRequests];

    [[NSNotificationCenter defaultCenter] removeObserver: _becomeActiveObserver];
    [[NSNotificationCenter defaultCenter] removeObserver: _willResignActiveObserver];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Private

- (void)checkAndPostWifiCredentialsIfAdhoc {
    LOG_CURRENT_METHOD;

    [IRHTTPClient cancelLocalRequests];

    // We don't want to POST wifi credentials without checking it's really IRKit
    // It's "Server" header prefix must be "IRKit/"

    __weak typeof(self) _self = self;
    [IRHTTPClient checkIfAdhocWithCompletion:^(NSHTTPURLResponse *res, BOOL isAdhoc, NSError *error) {
        LOG(@"isAdhoc: %d error: %@", isAdhoc, error);

        if (error && (error.code == NSURLErrorTimedOut) && [error.domain isEqualToString: NSURLErrorDomain]) {
            // if we've waited for XX seconds
            // we must haven't been connected to IRKit's Wi-Fi
            if ([[NSDate date] timeIntervalSinceDate: _self.becameActiveAt] > kWiFiConnectTimeout) {
                [_self alertAndHideHUD];
                return;
            }
            // retry if timeout
            LOG( @"retrying" );
            [_self performSelector: @selector(checkAndPostWifiCredentialsIfAdhoc)
                        withObject: Nil
                        afterDelay: 1.0];
            return;
        }

        if (isAdhoc) {

            NSString *localIP = [IRHelper localIPAddress];
            LOG( @"local IP: %@", localIP );
            NSRange found = [localIP rangeOfString: @"192.168.1."];
            if (found.location == NSNotFound) {
                // local IP must be 192.168.1.X when connected to IRKit wi-fi
                [_self alertAndHideHUD];
                return;
            }

            [IRHTTPClient postWifiKeys: [_self.keys morseStringRepresentation]
                        withCompletion : ^(NSHTTPURLResponse *res, id body, NSError *error) {
                LOG( @"res: %@, body: %@, error: %@", res, body, error );

                if (res.statusCode == 200) {
                    // hide HUD
                    [IRProgressView hideHUDForView: _self.view afterDelay: kIntervalToHideHUD];

                    _self.postWifiSucceeded = YES;
                    UIAlertController* c = [UIAlertController alertControllerWithTitle: IRLocalizedString(@"Great! Now let's connect back to your home Wi-Fi", @"alert title after POST /wifi finished successfully")
                                                                               message: @""
                                                                        preferredStyle: UIAlertControllerStyleAlert];
                    UIAlertAction* ok = [UIAlertAction actionWithTitle: @"OK" style: UIAlertActionStyleDefault
                                                               handler: ^(UIAlertAction* action) {}];
                    [c addAction: ok];
                    [self presentViewController: c animated: YES completion: nil];
                }
                else {
                    // this can't happen, IRKit responds with non 200 -> 400 when CRC is wrong, but that's not gonna happen
                    // retry if other errors
                    LOG( @"retrying" );
                    [_self performSelector: @selector(checkAndPostWifiCredentialsIfAdhoc)
                                withObject: Nil
                                afterDelay: 1.0];
                }
            }];
        }
        else {
            LOG( @"unexpected error res: %@ error: %@", res, error );

            // connected to different network?
            // don't retry
            [_self alertAndHideHUD];
        }
    }];
}

- (void) alertAndHideHUD {
    LOG_CURRENT_METHOD;
    [IRProgressView hideHUDForView: self.view afterDelay: kIntervalToHideHUD];

    UIAlertController* c = [UIAlertController alertControllerWithTitle: IRLocalizedString(@"Open Settings app and connect to a Wi-Fi network named like IRKitXXXX", @"alert title when reachable")
                                                               message: @""
                                                        preferredStyle: UIAlertControllerStyleAlert];
    UIAlertAction* ok = [UIAlertAction actionWithTitle: @"OK" style: UIAlertActionStyleDefault
                                               handler: ^(UIAlertAction* action) {}];
    [c addAction: ok];
    [self presentViewController: c animated: YES completion: nil];
}

- (void)startWaitingForDoor {
    if (_doorWaiter) {
        [_doorWaiter cancel];
    }
    __weak typeof(self) _self = self;
    _doorWaiter               = [IRHTTPClient waitForDoorWithDeviceID: _keys.deviceid completion:^(NSHTTPURLResponse *res, id object, NSError *error) {
        // hide HUD immediately
        [IRProgressView hideHUDForView: _self.view afterDelay: 0];

        if (error) {
            if (([error.domain isEqualToString: IRKitErrorDomainHTTP]) && (error.code == 401)) {
                UIAlertController* c = [UIAlertController alertControllerWithTitle: IRLocalizedString(@"Session expired, please restart app and try again.", @"alert title when POST /1/door returned 401")
                                                                           message: @""
                                                                    preferredStyle: UIAlertControllerStyleAlert];
                __weak typeof(self) _self = self;
                UIAlertAction* ok = [UIAlertAction actionWithTitle: @"OK" style: UIAlertActionStyleDefault
                                                           handler: ^(UIAlertAction* action) {
                                                               [_self.delegate guideWifiViewController: _self
                                                                                     didFinishWithInfo: @{
                                                                                                          IRViewControllerResultType: IRViewControllerResultTypeCancelled
                                                                                                          }];
                                                           }];
                [c addAction: ok];
                [self presentViewController: c animated: YES completion: nil];
            }
            return;
        }
        UIAlertController* c = [UIAlertController alertControllerWithTitle: IRLocalizedString(@"New IRKit found!", @"alert title when new IRKit is found")
                                                                   message: @""
                                                            preferredStyle: UIAlertControllerStyleAlert];
        UIAlertAction* ok = [UIAlertAction actionWithTitle: @"OK" style: UIAlertActionStyleDefault
                                                   handler: ^(UIAlertAction* action) {
                                                       IRPeripheral *p = [[IRKit sharedInstance].peripherals savePeripheralWithName: object[ @"hostname" ]
                                                                                                                           deviceid: _self.keys.deviceid];
                                                       // for debug purpose only; remember which regdomain we used to setup
                                                       p.regdomain = _self.keys.regdomain;

                                                       [_self.delegate guideWifiViewController: _self
                                                                             didFinishWithInfo: @{
                                                                                                  IRViewControllerResultType: IRViewControllerResultTypeDone,
                                                                                                  IRViewControllerResultPeripheral: p
                                                                                                  }];
                                                   }];
        [c addAction: ok];
        [self presentViewController: c animated: YES completion: nil];
    }];
}

- (void)doorWaiterTimeout:(NSTimer*)timer {
    [_doorWaiter cancel];
    _doorWaiter = nil;

    [_doorWaiterLimitTimer invalidate];
    _doorWaiterLimitTimer = nil;

    [IRProgressView hideHUDForView: self.view afterDelay: 0];

    UIAlertController* c = [UIAlertController alertControllerWithTitle: IRLocalizedString(@"IRKit couldn't connect to Wi-Fi. Check Wi-Fi settings and try again", @"alert title timeout")
                                                               message: @""
                                                        preferredStyle: UIAlertControllerStyleAlert];
    __weak typeof(self) _self = self;
    UIAlertAction* ok = [UIAlertAction actionWithTitle: @"OK"
                                                 style: UIAlertActionStyleDefault
                                               handler: ^(UIAlertAction* action) {
                                                   [[_self navigationController] popViewControllerAnimated: YES];
                                               }];
    [c addAction: ok];
    UIAlertAction* faq = [UIAlertAction actionWithTitle: IRLocalizedString(@"Show FAQ", @"title of button to FAQ on alert in IRGuideWiFiViewController")
                                                  style: UIAlertActionStyleDefault
                                                handler: ^(UIAlertAction* action) {
                                                    if (!_self) {
                                                        return;
                                                    }
                                                    // show FAQ
                                                    NSBundle *resources    = [IRHelper resources];
                                                    IRFAQViewController *c = [[IRFAQViewController alloc] initWithNibName: @"IRFAQViewController" bundle: resources];
                                                    c.delegate = _self;
                                                    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController: c];
                                                    [_self presentViewController: nc animated: YES completion:^{
                                                        LOG(@"presented");
                                                    }];
                                                }];
    [c addAction: faq];
    [self presentViewController: c animated: YES completion: nil];
}

#pragma mark - IRFAQViewControllerDelegate

- (void)faqViewControllerDidFinish:(IRFAQViewController *)controller {
    __weak typeof(self) _self = self;
    [self dismissViewControllerAnimated: YES completion:^{
        [_self.navigationController popViewControllerAnimated: YES];
    }];
}

@end
