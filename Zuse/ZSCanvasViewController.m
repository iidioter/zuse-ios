#import "ZSCanvasViewController.h"
#import "ZSRendererViewController.h"
#import "ZSGroupsViewController.h"
#import "ZSSpriteView.h"
#import "ZSCanvasView.h"
#import "ZSGeneratorView.h"
#import "ZSToolboxController.h"
#import "ZSToolboxView.h"
#import "ZSToolboxCell.h"
#import "ZSSpriteLibrary.h"
#import "ZSProjectPersistence.h"
#import "ZSCanvasBarButtonItem.h"
#import "ZSProjectJSONKeys.h"
#import "ZSZuseDSL.h"
#import "ZSCompiler.h"
#import <FontAwesomeKit/FAKIonIcons.h>
#import <AFNetworking/AFNetworking.h>
#import <Social/Social.h>
#import <Accounts/Accounts.h>
#import <MTBlockAlertView/MTBlockAlertView.h>
#import <SVProgressHUD/SVProgressHUD.h>
#import "ZSTutorial.h"
#import "ZSCompiler.h"
#import "ZSSocialZuseHubShareViewController.h"
#import "ZS_CodeEditorViewController.h"
#import "ZSTraitEditorViewController.h"
#import "ZSTraitToggleViewController.h"
#import "ZSSpriteTraits.h"

typedef NS_ENUM(NSInteger, ZSToolbarInterfaceState) {
    ZSToolbarInterfaceStateNormal,
    ZSToolbarInterfaceStateGroups,
    ZSToolbarInterfaceStateGenerators,
    ZSToolbarInterfaceStateRendererPlaying,
    ZSToolbarInterfaceStateRendererPaused,
    ZSToolbarInterfaceStateEditEmpty,
    ZSToolbarInterfaceStateEditNormalSprite,
    ZSToolbarInterfaceStateEditTextSprite,
    ZSToolbarInterfaceStateSubmenu
};

@interface ZSCanvasViewController ()

// Canvas
@property (weak, nonatomic) IBOutlet ZSCanvasView *canvasView;
@property (weak, nonatomic) IBOutlet UILabel *canvasLabel;

// Generator
@property (weak, nonatomic) IBOutlet ZSGeneratorView *generatorView;

// Renderer
@property (weak, nonatomic) IBOutlet UIView *rendererView;
@property (strong, nonatomic) ZSRendererViewController *rendererViewController;

// Tutorial
@property (strong, nonatomic) ZSTutorial *tutorial;

// Toolbox
@property (strong, nonatomic) ZSToolboxView *toolboxView;
@property (strong, nonatomic) ZSToolboxController *toolboxController;

// Grouping
@property (strong, nonatomic) ZSGroupsViewController *groupsController;

// Toolbar
@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property (weak, nonatomic) IBOutlet UIToolbar *submenu;
@property (nonatomic, assign) BOOL submenuShowing;
@property (assign, nonatomic) ZSToolbarInterfaceState interfaceState;

// Grid
@property (assign, nonatomic) BOOL gridSliderShowing;
@property (weak, nonatomic) IBOutlet UIView *gridSlider;
@property (weak, nonatomic) IBOutlet UILabel *smallGridLabel;
@property (weak, nonatomic) IBOutlet UILabel *gridLabel;

// ZuseHub and Social Share
@property (strong, nonatomic) UIActionSheet *actionSheet;
@property (strong, nonatomic) UIButton *twitterButton;
@property (strong, nonatomic) UIButton *facebookButton;
@property (strong, nonatomic) UIButton *zuseHubButton;

@end

@implementation ZSCanvasViewController

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        _tutorial = [ZSTutorial sharedTutorial];
        _toolboxController = [[ZSToolboxController alloc] init];
        _gridSliderShowing = NO;
        _submenuShowing = NO;
        self.interfaceState = ZSToolbarInterfaceStateNormal;
    }
    return self;
}

#pragma mark Override Methods

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Load the project if it exists.
    CGFloat scale = 1;
    if (_project) {
        // Setup pieces of the canvas.
        [self setupCanvas];
        [self setupGenerators];
        [self setupToolbar];
        [self setupSubmenu];
        [self setupToolbox];
        
        // Setup aspect ratio of project based on the size of the phone.
        CGRect canvasFrames = [[UIScreen mainScreen] bounds];
        canvasFrames.size.height -= 44;
        self.canvasView.frame = canvasFrames;
        self.rendererView.frame = canvasFrames;
        self.generatorView.frame = canvasFrames;
        
        CGRect gridSliderFrame = self.gridSlider.frame;
        gridSliderFrame.size.height = 42; // For some reason it's not getting set correctly.
        gridSliderFrame.origin.y = canvasFrames.size.height;
        self.gridSlider.frame = gridSliderFrame;
        
        NSArray *sizeArray = self.project.rawJSON[@"canvas_size"];
        CGFloat projectHeight = [sizeArray[1] floatValue];
        scale = canvasFrames.size.height / projectHeight;
        
        // Set a curved radius on the canvas label.
        self.canvasLabel.layer.cornerRadius = 10;
        
        [self.smallGridLabel setAttributedText:[FAKIonIcons gridIconWithSize:20].attributedString];
        [self.gridLabel setAttributedText:[FAKIonIcons gridIconWithSize:30].attributedString];
        
        // Load Sprites and generators.
        [self loadSpritesAndGeneratorsFromProject];
    }
    
    [self transitionToInterfaceState:ZSToolbarInterfaceStateNormal];
    
    // Animate in the canvas view and all that jazz
    [self animateCanvasViewIn];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES];
    self.navigationController.navigationBarHidden = YES;
    
    // TODO: Figure out the correct place to put this.  The editor may have modified the project
    // so save the project here as well.  This means that the project gets loaded and then saved
    // right away on creation as well.
    [self saveProject];
    [self.view setNeedsDisplay];
    
    [self.tutorial broadcastEvent:ZSTutorialBroadcastEventComplete];
}

- (void)viewDidAppear:(BOOL)animated {
    if (_tutorial.isActive) {
        [self createTutorialForStage:_tutorial.stage];
        [_tutorial present];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"renderer"]) {
        ZSRendererViewController *rendererController = (ZSRendererViewController *)segue.destinationViewController;
        rendererController.projectJSON = [_project assembledJSON];
        _rendererViewController = rendererController;
    } else if ([segue.identifier isEqualToString:@"editor"]) {
        ZS_CodeEditorViewController *codeController = (ZS_CodeEditorViewController *)segue.destinationViewController;
        NSMutableDictionary *spriteObject = ((ZSSpriteView *)sender).spriteJSON;
        codeController.codeItems = spriteObject[@"code"];
        codeController.initialProperties = spriteObject[@"properties"];
    } else if ([segue.identifier isEqualToString:@"traitToggle"]) {
        NSMutableDictionary *spriteObject = ((ZSSpriteView *)sender).spriteJSON;
        ZSTraitToggleViewController *traitController = (ZSTraitToggleViewController *)segue.destinationViewController;
        if (!spriteObject[@"traits"]) {
            spriteObject[@"traits"] = [NSMutableDictionary dictionary];
        }
        traitController.enabledSpriteTraits  = spriteObject[@"traits"];
        traitController.projectTraits = [self.project assembledJSON][@"traits"];
        traitController.globalTraits  = [ZSSpriteTraits defaultTraits];
        traitController.spriteProperties = spriteObject[@"properties"];
    } else if ([segue.identifier isEqualToString:@"traitEdit"]) {
        ZSTraitEditorViewController *traitController = (ZSTraitEditorViewController *)segue.destinationViewController;
        traitController.projectTraits = [self.project assembledJSON][@"traits"];
        traitController.globalTraits  = [ZSSpriteTraits defaultTraits];
    }
}

#pragma mark Segue Setup

- (void)canvasSegueWithIdentifier:(NSString *)identifier sender:(id)sender {
    if (self.gridSliderShowing) {
        [self hideSliderWithHandler:^{
            [self performSegueWithIdentifier:identifier sender:sender];
        }];
    }
    else if (self.submenuShowing) {
        [self hideSubmenuWithHandler:^{
            [self performSegueWithIdentifier:identifier sender:sender];
        }];
    }
    else {
        [self performSegueWithIdentifier:identifier sender:sender];
    }
}

#pragma mark Transition Animations

- (void)animateCanvasViewIn {
    CGRect toolbarFrame = self.toolbar.frame;
    CGRect originalToolbarFrame = toolbarFrame;
    toolbarFrame.origin.y = self.view.bounds.size.height;
    self.toolbar.frame = toolbarFrame;
    
    CGRect normalFrame = self.canvasView.frame;
    self.view.backgroundColor = [UIColor clearColor];
    CGFloat scale = self.initialCanvasRect.size.width / self.view.bounds.size.width;
    self.canvasView.transform = CGAffineTransformMakeScale(scale, scale);
    CGRect frame = self.canvasView.frame;
    frame.origin.x = self.initialCanvasRect.origin.x;
    frame.origin.y = self.initialCanvasRect.origin.y;
    self.canvasView.frame = frame;
    
    self.gridSlider.hidden = YES;
    self.submenu.hidden = YES;
    [UIView animateWithDuration:0.4
                     animations:^{
                         self.canvasView.transform = CGAffineTransformIdentity;
                         self.canvasView.frame = normalFrame;
                         self.toolbar.frame = originalToolbarFrame;
                     } completion:^(BOOL finished) {
                         self.gridSlider.hidden = NO;
                         self.submenu.hidden = NO;
                     }];
}

- (void)animateCanvasViewOut {
    if (!self.generatorView.hidden) {
        self.generatorView.hidden = YES;
    }
    CGFloat scale = self.initialCanvasRect.size.width / self.canvasView.bounds.size.width;
    CGRect toolbarRect = self.toolbar.frame;
    toolbarRect.origin.y = self.view.bounds.size.height;
    
    self.gridSlider.hidden = YES;
    self.submenu.hidden = YES;
    [UIView animateWithDuration:0.4
                     animations:^{
                         self.canvasView.transform = CGAffineTransformMakeScale(scale, scale);
                         self.canvasView.frame = self.initialCanvasRect;
                         self.toolbar.frame = toolbarRect;
                         
                     } completion:^(BOOL finished) {
                         self.rendererView = nil;
                         self.rendererViewController = nil;
                         if (self.didFinish) {
                             self.didFinish();
                         }
                     }];
}

#pragma mark Tutorial

- (void)createTutorialForStage:(ZSTutorialStage)stage {
    WeakSelf
    __block UIView *paddle1 = nil;
    __block UIView *paddle2 = nil;
    __block UIView *ball = nil;
    
    CGRect settingsButtonRect = ((ZSCanvasBarButtonItem *)_toolbar.items[2]).button.frame;
    CGRect playButtonRect = ((ZSCanvasBarButtonItem *)_toolbar.items[6]).button.frame;
    CGRect editButtonRect = ((ZSCanvasBarButtonItem *)_toolbar.items[3]).button.frame;
    
    if (stage == ZSTutorialSetupStage) {
        UICollectionView *collectionView = (UICollectionView*)[_toolboxView viewByIndex:0];
        CGRect ballRect = [collectionView layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]].frame;
        ballRect.size.height -= 17;
        CGRect paddleRect = [collectionView layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]].frame;
        paddleRect.size.height -= 17;
        
        [_tutorial addActionWithText:@"Zuse allows you to build games on your iPhone.  This tutorial will teach you how to build Pong.  Tap anywhere to continue."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:CGRectZero
                               setup:nil
                          completion:nil];
        [_tutorial addActionWithText:@"This screen you are on right now is called the Canvas, which is where you lay out your game visually.  Our Pong game will have two paddles, one on top of the screen and one on bottom, and a ball that bounces around the screen."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:CGRectZero
                               setup:nil
                          completion:nil];
        [_tutorial addActionWithText:@"Tap here to open the Toolbox."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:[_toolbar convertRect:settingsButtonRect toView:weakSelf.view]
                               setup:nil
                          completion:nil];
        [_tutorial addActionWithText:@"The Toolbox contains Sprites, which are images and text boxes you can give behavior to.  Tap-and-hold this paddle sprite and place it near the top of the Canvas."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UILongPressGestureRecognizer.class]
                        activeRegion:[collectionView convertRect:paddleRect toView:weakSelf.view]
                               setup:nil
                          completion:^{
                              paddle1 = [weakSelf.canvasView.subviews lastObject];
                              [weakSelf.tutorial saveObject:paddle1 forKey:@"paddle1"];
                              [weakSelf showToolbox];
                          }];
        [_tutorial addActionWithText:@"Tap-and-hold again and lay this paddle at the bottom of the Canvas."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UILongPressGestureRecognizer.class]
                        activeRegion:[collectionView convertRect:paddleRect toView:weakSelf.view]
                               setup:nil
                          completion:^{
                              paddle2 = [weakSelf.canvasView.subviews lastObject];
                              [weakSelf.tutorial saveObject:paddle2 forKey:@"paddle2"];
                              [weakSelf showToolbox];
                          }];
        [_tutorial addActionWithText:@"Put the ball near the center of the screen."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UILongPressGestureRecognizer.class]
                        activeRegion:[collectionView convertRect:ballRect toView:weakSelf.view]
                               setup:nil
                          completion:^{
                              ball = [weakSelf.canvasView.subviews lastObject];
                              [weakSelf.tutorial saveObject:ball forKey:@"ball"];
                          }];
        [_tutorial addActionWithText:@"Great job!  This Play button will run your game at any time.  Try pressing it now."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:[_toolbar convertRect:playButtonRect toView:weakSelf.view]
                               setup:nil
                          completion:nil];
        [_tutorial addActionWithText:@"Our game is now running! Try dragging a paddle. Nothing works! Our ball isn’t moving, either. That’s because we have to tell our Sprites what to do by giving them code that will run when we press the Play button. Let’s create some code to make the ball move! Tap the Stop button to stop the game and go back to the Canvas."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:[_toolbar convertRect:CGRectNull toView:weakSelf.view]
                               setup:^{
                                   CGRect stopButtonRect = ((ZSCanvasBarButtonItem *)weakSelf.toolbar.items[1]).button.frame;
                                   stopButtonRect = [weakSelf.view convertRect:stopButtonRect fromView:weakSelf.toolbar.viewForBaselineLayout];
                                   weakSelf.tutorial.overlayView.activeRegion = stopButtonRect;
                               }
                          completion:nil];
        [_tutorial addActionWithText:@"Let's start by making the ball move. You can tap any sprite to bring up the Sprite Editor, where we give sprites behavior. Tap the ball so we can give it some Code!"
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:CGRectZero
                               setup:^{
                                   ball = [weakSelf.tutorial getObjectForKey:@"ball"];
                                   weakSelf.tutorial.overlayView.activeRegion = ball.frame;
                               }
                          completion:nil];
    }
    else if (stage == ZSTutorialPaddleStage) {
        [_tutorial addActionWithText:@"Now all that is left is to make the paddle move when touched.  The actual code to do this can be complicated so Zuse provides a Trait for it.  A Trait in Zuse is a section of Code that can be shared across multiple Sprites.  In this case both paddles will use the same Code or in this case Trait to move when the user drags them."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:CGRectZero
                               setup:nil
                          completion:nil];
        [_tutorial addActionWithText:@"To add a Trait to a Sprite first click the edit button to put the Canvas into edit mode."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:[_toolbar convertRect:editButtonRect toView:weakSelf.view]
                               setup:nil
                          completion:nil];
        [_tutorial addActionWithText:@"Now touch the paddle to bring up it's edit options."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:CGRectZero
                               setup:^{
                                   paddle1 = [weakSelf.tutorial getObjectForKey:@"paddle1"];
                                   weakSelf.tutorial.overlayView.activeRegion = paddle1.frame;
                               }
                          completion:nil];
        [_tutorial addActionWithText:@"This menu item will bring you to a list of all Traits.  Touch it to continue."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:[_toolbar convertRect:CGRectNull toView:weakSelf.view]
                               setup:^{
                                   CGRect propertiesButtonRect = ((ZSCanvasBarButtonItem *)weakSelf.toolbar.items[5]).button.frame;
                                   propertiesButtonRect = [weakSelf.view convertRect:propertiesButtonRect fromView:weakSelf.toolbar.viewForBaselineLayout];
                                   weakSelf.tutorial.overlayView.activeRegion = propertiesButtonRect;
                               }
                          completion:nil];
        [_tutorial addActionWithText:@"This is the Draggable Trait.  By simply enabling the Draggable Trait the paddle will become draggable."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:CGRectMake(8, 34, 311, 55)
                               setup:nil
                          completion:nil];
        [_tutorial addActionWithText:@"The Draggable Trait enables the Sprite to be dragged in both the horizontal and vertical directions.  For Pong we only want a paddle to be dragged in the horizontal direction so lets go and change the options by touching here."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:CGRectMake(246, 34, 73, 55)
                               setup:nil
                          completion:nil];
        [_tutorial addActionWithText:@"We don't want the paddle to be dragged vertically so touch here to turn off that option."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:CGRectMake(8, 34, 311, 55)
                               setup:nil
                          completion:nil];
        [_tutorial addActionWithText:@"Press Back to go back to the canvas."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:CGRectMake(0, 0, 84, 42)
                               setup:nil
                          completion:nil];
    }
    else if (stage == ZSTutorialFinalStage)  {
        [_tutorial addActionWithText:@"Congradulations.  You have finished the tutorial.  Now that you have seen how to set up a paddle to be dragged feel free to set up the last paddle in the same way.  We are still in the edit mode.  If you would like to exit edit mode please select the checkmark which will bring you back to the Canvas."
                            forEvent:ZSTutorialBroadcastEventComplete
                     allowedGestures:@[UITapGestureRecognizer.class]
                        activeRegion:CGRectZero
                               setup:nil
                          completion:nil];
    }
}

#pragma mark Project Management

- (void)loadSpritesAndGeneratorsFromProject {
    NSMutableDictionary *assembledJSON = [_project assembledJSON];
    for (NSMutableDictionary *jsonObject in assembledJSON[@"objects"]) {
        [self.canvasView addSpriteFromJSON:jsonObject];
    }
    
    for (NSMutableDictionary *jsonObject in assembledJSON[@"generators"]) {
        [self.generatorView addGeneratorFromJSON:jsonObject];
    }
}

- (void)saveProject {
    UIGraphicsBeginImageContext(_canvasView.bounds.size);
    [_canvasView.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    self.project.screenshot = image;
    
    [ZSProjectPersistence writeProject:self.project];
}

#pragma mark Canvas Setup

- (void)setupCanvas {
    WeakSelf
    
    _canvasView.spriteSingleTapped = ^(ZSSpriteView *spriteView) {
        [_tutorial broadcastEvent:ZSTutorialBroadcastEventComplete];
        [self canvasSegueWithIdentifier:@"editor" sender:spriteView];
    };
    
    _canvasView.spriteCreated = ^(ZSSpriteView *spriteView) {
        [[_project rawJSON][@"objects"] addObject:spriteView.spriteJSON];
        [weakSelf saveProject];
    };
    
    _canvasView.spriteRemoved = ^(ZSSpriteView *spriteView) {
        NSMutableArray *objects = [weakSelf.project rawJSON][@"objects"];
        [objects removeObject:spriteView.spriteJSON];
        [weakSelf saveProject];
    };
    
    _canvasView.spriteModified = ^(ZSSpriteView *spriteView) {
        [weakSelf saveProject];
    };
    
    _canvasView.spriteSelected = ^(ZSSpriteView *spriteView) {
        NSString *type = spriteView.spriteJSON[@"type"];
        if ([type isEqualToString:@"image"]) {
            [weakSelf transitionToInterfaceState:ZSToolbarInterfaceStateEditNormalSprite];
        }
        else if ([type isEqualToString:@"text"]) {
            [weakSelf transitionToInterfaceState:ZSToolbarInterfaceStateEditTextSprite];
        }
        [self hideSliderWithHandler:nil];
        [self hideSubmenuWithHandler:nil];
        [self.tutorial broadcastEvent:ZSTutorialBroadcastEventComplete];
    };
    
    _canvasView.singleTapped = ^() {
        [self hideSliderWithHandler:nil];
        [self hideSubmenuWithHandler:nil];
    };
}

#pragma mark Setup Generators

- (void)setupGenerators {
    WeakSelf
    
    _generatorView.singleTapped = ^(ZSSpriteView *spriteView) {
        [self performSegueWithIdentifier:@"editor" sender:spriteView];
    };
    
    _generatorView.generatorRemoved = ^(ZSSpriteView *spriteView) {
        NSMutableArray *generators = [weakSelf.project rawJSON][@"generators"];
        [generators removeObject:spriteView.spriteJSON];
        [weakSelf saveProject];
        [_generatorView reloadData];
    };
    
    _generatorView.addGeneratorRequested = ^ {
        [weakSelf showToolbox];
    };
}

#pragma mark Toolbox

- (void)setupToolbox {
    [self setupToolboxController];
    
    CGFloat height = 82;
    if ([[UIScreen mainScreen] bounds].size.height == 480) {
        height = 38;
    }
    _toolboxView = [[ZSToolboxView alloc] initWithFrame:CGRectMake(19, height, 282, 361)];
    
    WeakSelf
    _toolboxView.hidView = ^{
        [weakSelf.tutorial broadcastEvent:ZSTutorialBroadcastEventComplete];
    };
    NSMutableArray *categories = [ZSSpriteLibrary sharedLibrary].categories;
    for (int i = 0; i < categories.count; i++) {
        UICollectionView *collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[[UICollectionViewFlowLayout alloc] init]];
        [collectionView registerClass:ZSToolboxCell.class forCellWithReuseIdentifier:@"cellID"];
        collectionView.userInteractionEnabled = YES;
        collectionView.contentInset = UIEdgeInsetsMake(4, 4, 4, 4);
        collectionView.delegate = _toolboxController;
        collectionView.dataSource = _toolboxController;
        collectionView.tag = i;
        
        [_toolboxView addContentView:collectionView title:categories[i][@"category"]];
    }
    // UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    // [button setTitle:@"Import Image" forState:UIControlStateNormal];
    // [_toolboxView addButton:button];
    [self.view addSubview:_toolboxView];
}

- (void)setupToolboxController {
    WeakSelf
    
    __block CGPoint offset;
    __block CGPoint currentPoint;
    __block ZSSpriteView *draggedView;
    _toolboxController.longPressBegan = ^(UILongPressGestureRecognizer *panGestureRecognizer) {
        ZSSpriteView *spriteView = (ZSSpriteView*)panGestureRecognizer.view;
        NSMutableDictionary *json = [spriteView.spriteJSON deepMutableCopy];
        NSString *type = json[@"type"];
        if ([@"text" isEqualToString:type]) {
            json[@"properties"][@"text"] = @"Value";
        }
        json[ZSProjectJSONKeyGroup] = @"";
        
        // Width and height of frame can be calculated now.
        CGRect originalFrame = spriteView.content.frame;
        CGRect frame = CGRectZero;
        frame.size.width = [json[@"properties"][@"width"] floatValue];
        frame.size.height = [json[@"properties"][@"height"] floatValue];
        
        // If the generator view is hidden start sprite dragging, otherwise simply add it to the
        // generator view.
        if (weakSelf.generatorView.hidden && ![weakSelf.canvasView inEditMode]) {
            if (![@"text" isEqualToString:type]) {
                CGFloat scale = frame.size.width / spriteView.content.frame.size.width;
                offset = [panGestureRecognizer locationInView:spriteView.content];
                offset = CGPointMake(offset.x * scale, offset.y * scale);
            }
            else {
                offset = [panGestureRecognizer locationInView:spriteView];
                offset = CGPointMake(offset.x, frame.size.height / 2);
            }
            currentPoint = [panGestureRecognizer locationInView:weakSelf.canvasView];
            
            originalFrame.origin.x = currentPoint.x - offset.x;
            originalFrame.origin.y = currentPoint.y - offset.y;
            
            frame.origin.x = currentPoint.x - offset.x;
            frame.origin.y = currentPoint.y - offset.y;
            
            draggedView = [[ZSSpriteView alloc] initWithFrame:frame];
            [draggedView setContentFromJSON:json];
            [weakSelf.canvasView addSubview:draggedView];
            
            CGFloat scale = spriteView.content.frame.size.width / frame.size.width;
            if (scale < 1) {
                draggedView.transform = CGAffineTransformMakeScale(scale, scale);
                [UIView animateWithDuration:0.25f animations:^{
                    draggedView.transform = CGAffineTransformIdentity;
                }];
            }
        }
        else if ([weakSelf.canvasView inEditMode]) {
            [weakSelf.canvasView replaceSelectedSpriteWithJSON:json];
        }
        else {
            MTBlockAlertView *alertView = [[MTBlockAlertView alloc]
                                           initWithTitle:@"Generator"
                                           message:@"Enter a name for the generator."
                                           completionHanlder:^(UIAlertView *alertView, NSInteger buttonIndex) {
                                               NSString *name = [alertView textFieldAtIndex:0].text;
                                               if (![name isEqualToString:@""]) {
                                                   NSMutableDictionary *newJson = [json deepMutableCopy];
                                                   newJson[@"id"] = [[NSUUID UUID] UUIDString];
                                                   newJson[@"name"] = name;
                                                   newJson[@"properties"][@"x"] = @(0);
                                                   newJson[@"properties"][@"y"] = @(0);
                                                   newJson[@"properties"][@"angle"] = @(0);
                                                   newJson[@"properties"][@"hidden"] = @(0);
                                                   [[weakSelf.project rawJSON][@"generators"] insertObject:newJson atIndex:0];
                                                   
                                                   [weakSelf.generatorView insertGeneratorFromJSON:newJson];
                                                   [weakSelf.generatorView reloadData];
                                                   [weakSelf saveProject];
                                                }
                                           }
                                           cancelButtonTitle:@"OK"
                                           otherButtonTitles:nil];
            alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
            [alertView show];
        }
        [weakSelf.toolboxView hideAnimated:YES];
        [weakSelf.tutorial hideMessage];
    };
    
    _toolboxController.longPressChanged = ^(UILongPressGestureRecognizer *longPressGestureRecognizer) {
        if (weakSelf.generatorView.hidden && ![weakSelf.canvasView inEditMode]) {
            currentPoint = [longPressGestureRecognizer locationInView:weakSelf.canvasView];
            [weakSelf.canvasView moveSprite:draggedView x:currentPoint.x - offset.x y:currentPoint.y - offset.y];
        }
    };
    
    _toolboxController.longPressEnded = ^(UILongPressGestureRecognizer *longPressGestureRecognizer) {
        if (weakSelf.generatorView.hidden && ![weakSelf.canvasView inEditMode]) {
            NSMutableDictionary *json = draggedView.spriteJSON;
            
            NSMutableDictionary *newJson = [json deepMutableCopy];
            newJson[@"id"] = [[NSUUID UUID] UUIDString];
            NSMutableDictionary *properties = newJson[@"properties"];
            [[weakSelf.project rawJSON][@"objects"] addObject:newJson];
            
            CGFloat x = draggedView.frame.origin.x + (draggedView.frame.size.width / 2);
            CGFloat y = weakSelf.canvasView.frame.size.height - draggedView.frame.size.height - draggedView.frame.origin.y;
            y += draggedView.frame.size.height / 2;
            
            properties[@"x"] = @(x);
            properties[@"y"] = @(y);
            properties[@"angle"] = @(0);
            properties[@"hidden"] = @(0);
            
            draggedView.spriteJSON = newJson;
            [weakSelf.canvasView setupGesturesForSpriteView:draggedView withProperties:properties];
            [weakSelf.canvasView setupEditOptionsForSpriteView:draggedView];
            
            // Save the project.
            [weakSelf saveProject];
            [weakSelf.tutorial broadcastEvent:ZSTutorialBroadcastEventComplete];
        }
    };
}

#pragma mark Toolbar

- (void)setupToolbar {
    self.toolbar.translucent = NO;
    self.toolbar.barTintColor = [UIColor zuseBackgroundGrey];
    self.toolbar.clipsToBounds = YES;
}

- (void)setupSubmenu {
    self.submenu.translucent = NO;
    self.submenu.barTintColor = [UIColor zuseBackgroundGrey];
    self.submenu.clipsToBounds = YES;
    [self.submenu setItems:[self submenuToolbarItems]];
}

- (void)transitionToInterfaceState:(ZSToolbarInterfaceState)state {
    NSArray *items = nil;
    if (state == ZSToolbarInterfaceStateNormal) {
        items = [self normalToolbarItems];
    } else if (state == ZSToolbarInterfaceStateGroups) {
        items = [self groupsToolbarItems];
    } else if (state == ZSToolbarInterfaceStateRendererPlaying) {
        items = [self rendererPlayingToolbarItems];
    } else if (state == ZSToolbarInterfaceStateRendererPaused) {
        items = [self rendererPausedToolbarItems];
    } else if (state == ZSToolbarInterfaceStateGenerators) {
        items = [self generatorsToolbarItems];
    } else if (state == ZSToolbarInterfaceStateEditEmpty) {
        items = [self editSpritesEmpty];
    } else if (state == ZSToolbarInterfaceStateEditNormalSprite) {
        items = [self editNormalSprite];
    } else if (state == ZSToolbarInterfaceStateEditTextSprite) {
        items = [self editTextSprite];
    } else if (state == ZSToolbarInterfaceStateSubmenu) {
        items = [self submenuToolbarItems];
    }
    
    self.interfaceState = state;
    
    [self.toolbar setItems:items animated:YES];
}

- (NSArray *)normalToolbarItems {
    WeakSelf
    return @[
             [ZSCanvasBarButtonItem backButtonWithHandler:^{
                 [weakSelf finish];
             }],
             [ZSCanvasBarButtonItem flexibleBarButtonItem],
             [ZSCanvasBarButtonItem toolboxButtonWithHandler:^{
                 [weakSelf showToolbox];
                 [self.tutorial broadcastEvent:ZSTutorialBroadcastEventComplete];
             }],
             [ZSCanvasBarButtonItem editButtonWithHandler:^{
                 [self hideSubmenuWithHandler:^{
                     [self.canvasView activateEditMode];
                     [self transitionToInterfaceState:ZSToolbarInterfaceStateEditEmpty];
                     [self.tutorial broadcastEvent:ZSTutorialBroadcastEventComplete];
                 }];
             }],
             [ZSCanvasBarButtonItem gridButtonWithHandler:^{
                 [weakSelf toggleSliderViewWithHandler:nil];
             }],
             [ZSCanvasBarButtonItem menuButtonWithHandler:^{
                 [weakSelf toggleSubmenuViewWithHandler:nil];
//                 [weakSelf transitionToInterfaceState:ZSToolbarInterfaceStateSubmenu];
             }],
             [ZSCanvasBarButtonItem playButtonWithHandler:^{
                 if (weakSelf.gridSliderShowing) {
                     [weakSelf hideSliderWithHandler:^{
                         [weakSelf playProject];
                     }];
                 }
                 else if (weakSelf.submenuShowing) {
                     [weakSelf hideSubmenuWithHandler:^{
                         [weakSelf playProject];
                     }];
                 }
                 else {
                     [weakSelf playProject];
                 }
                 [self.tutorial broadcastEvent:ZSTutorialBroadcastEventComplete];
             }]
             ];
}

- (NSArray *)groupsToolbarItems {
    return self.groupsController.canvasToolbarItems;
}

// These items are for the submenu not the main toolbar.
- (NSArray *)submenuToolbarItems {
    WeakSelf
    return @[
             [ZSCanvasBarButtonItem flexibleBarButtonItem],
             [ZSCanvasBarButtonItem propertiesButtonWithHandler:^{
                 [self canvasSegueWithIdentifier:@"traitEdit" sender:self.canvasView];
             }],
             [ZSCanvasBarButtonItem groupsButtonWithHandler:^{
                 [self hideSubmenuWithHandler:^{
                     if (weakSelf.gridSliderShowing) {
                         [weakSelf hideSliderWithHandler:^{
                             [weakSelf modifyGroups];
                         }];
                     }
                     else if (weakSelf.submenuShowing) {
                         [weakSelf hideSubmenuWithHandler:^{
                             [weakSelf modifyGroups];
                         }];
                     }
                     else {
                         [weakSelf modifyGroups];
                     }
                 }];
                 
             }],
             [ZSCanvasBarButtonItem generatorsButtonWithHandler:^{
                 [self hideSubmenuWithHandler:^{
                     if (weakSelf.gridSliderShowing) {
                         [weakSelf hideSliderWithHandler:^{
                             [weakSelf toggleGeneratorView];
                         }];
                     }
                     else if (weakSelf.submenuShowing) {
                         [weakSelf hideSubmenuWithHandler:^{
                             [weakSelf toggleGeneratorView];
                         }];
                     }
                     else {
                         [weakSelf toggleGeneratorView];
                     }
                 }];
                 
             }],
             [ZSCanvasBarButtonItem shareButtonWithHandler:^{
                 [self hideSubmenuWithHandler:^{
                     //TODO present custom UIActivityViewController as you would w/ any normal view controller

                     [self shareProjectWithCompletion:^(NSString *URL) {
                         ZSSocialZuseHubShareViewController *socialZuseHubShareController = [[ZSSocialZuseHubShareViewController alloc] initWithProject:self.project URL:[NSURL URLWithString:URL]];

                         socialZuseHubShareController.didFinish = ^{
                             [self dismissViewControllerAnimated:YES completion:^{}];
                         };
                         socialZuseHubShareController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
                         [weakSelf presentViewController:socialZuseHubShareController animated:YES completion:^{}];
                         
                     }];

                 }];
             }]
             ];
}

- (NSArray *)rendererPlayingToolbarItems {
    WeakSelf
    return @[
             [ZSCanvasBarButtonItem flexibleBarButtonItem],
             [ZSCanvasBarButtonItem stopButtonWithHandler:^{
                 [weakSelf stopProject];
                 [weakSelf.tutorial broadcastEvent:ZSTutorialBroadcastEventComplete];
             }],
             [ZSCanvasBarButtonItem pauseButtonWithHandler:^{
                 [weakSelf pauseProject];
             }]
             ];
}

- (NSArray *)rendererPausedToolbarItems {
    WeakSelf
    return @[
             [ZSCanvasBarButtonItem flexibleBarButtonItem],
             [ZSCanvasBarButtonItem stopButtonWithHandler:^{
                 [weakSelf stopProject];
             }],
             [ZSCanvasBarButtonItem playButtonWithHandler:^{
                 [weakSelf playProject];
             }]
             ];
}

- (NSArray *)generatorsToolbarItems {
    WeakSelf
    return @[
             [ZSCanvasBarButtonItem flexibleBarButtonItem],
             [ZSCanvasBarButtonItem groupsButtonWithHandler:^{
                 [weakSelf modifyGroups];
             }],
             [ZSCanvasBarButtonItem finishButtonWithHandler:^{
                 [weakSelf toggleGeneratorView];
             }]
             ];
}

- (NSArray *)editSpritesEmpty {
    WeakSelf
    return @[
             [ZSCanvasBarButtonItem flexibleBarButtonItem],
             [ZSCanvasBarButtonItem finishButtonWithHandler:^{
                 [weakSelf.canvasView deactivateEditMode];
                 [weakSelf transitionToInterfaceState:ZSToolbarInterfaceStateNormal];
             }]
             ];
}

- (NSArray *)editNormalSprite {
    WeakSelf
    return @[
             [ZSCanvasBarButtonItem flexibleBarButtonItem],
             [ZSCanvasBarButtonItem cutButtonWithHandler:^{
                 [weakSelf.canvasView cutSelectedSprite];
             }],
             [ZSCanvasBarButtonItem copyButtonWithHandler:^{
                 [weakSelf.canvasView copySelectedSprite];
             }],
             [ZSCanvasBarButtonItem deleteButtonWithHandler:^{
                 [weakSelf.canvasView deleteSelectedSprite];
                 [weakSelf transitionToInterfaceState:ZSToolbarInterfaceStateEditEmpty];
             }],
             [ZSCanvasBarButtonItem swapButtonWithHandler:^{
                 [weakSelf showToolbox];
             }],
             [ZSCanvasBarButtonItem propertiesButtonWithHandler:^{
                 [self canvasSegueWithIdentifier:@"traitToggle" sender:weakSelf.canvasView.selectedSprite];
                 [self.tutorial broadcastEvent:ZSTutorialBroadcastEventComplete];
             }],
             [ZSCanvasBarButtonItem finishButtonWithHandler:^{
                 [weakSelf saveProject];
                 [weakSelf.canvasView deactivateEditMode];
                 [weakSelf transitionToInterfaceState:ZSToolbarInterfaceStateNormal];
             }]
             ];
}

- (NSArray *)editTextSprite {
    WeakSelf
    void (^doneBlock)() = ^{
        [weakSelf saveProject];
        [weakSelf.canvasView deactivateEditMode];
        [weakSelf transitionToInterfaceState:ZSToolbarInterfaceStateNormal];
    };
    return @[
             [ZSCanvasBarButtonItem flexibleBarButtonItem],
             [ZSCanvasBarButtonItem cutButtonWithHandler:^{
                 [weakSelf.canvasView cutSelectedSprite];
                 doneBlock();
             }],
             [ZSCanvasBarButtonItem copyButtonWithHandler:^{
                 [weakSelf.canvasView copySelectedSprite];
                 doneBlock();
             }],
             [ZSCanvasBarButtonItem deleteButtonWithHandler:^{
                 [weakSelf.canvasView deleteSelectedSprite];
                 doneBlock();
             }],
             [ZSCanvasBarButtonItem editTextButtonWithHandler:^{
                 MTBlockAlertView *alertView = [[MTBlockAlertView alloc]
                                                initWithTitle:@"Sprite Text"
                                                message:@"Enter the sprite text."
                                                completionHanlder:^(UIAlertView *alertView, NSInteger buttonIndex) {
                                                    NSString *text = [alertView textFieldAtIndex:0].text;
                                                    [weakSelf.canvasView setTextForSelectedSpriteWithText:text];
                                                    [weakSelf saveProject];
                                                }
                                                cancelButtonTitle:@"OK"
                                                otherButtonTitles:nil];
                 alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
                 [alertView show];
             }],
             [ZSCanvasBarButtonItem finishButtonWithHandler:^{
                 [weakSelf.canvasView deactivateEditMode];
                 [weakSelf transitionToInterfaceState:ZSToolbarInterfaceStateNormal];
             }]
             ];
}

- (void)playProject {
    [self transitionToInterfaceState:ZSToolbarInterfaceStateRendererPlaying];
    
    [self.view bringSubviewToFront:self.rendererView];
    if (self.rendererView.hidden) {
        self.rendererViewController.projectJSON = [self.project assembledJSON];
        self.rendererView.hidden = NO;
        [self.rendererViewController play];
    }
    else {
        [self.rendererViewController resume];
    }
}

- (void)pauseProject {
    [_rendererViewController stop];
    [self transitionToInterfaceState:ZSToolbarInterfaceStateRendererPaused];
}


- (void)stopProject {
    [self.rendererViewController stop];
    self.rendererView.hidden = YES;
    [self transitionToInterfaceState:ZSToolbarInterfaceStateNormal];
}

- (void)toggleGeneratorView {
    // Setup
    BOOL generatorHidden = self.generatorView.hidden;
    if (generatorHidden) {
        self.generatorView.alpha = 0;
        self.generatorView.hidden = NO;
        [self.view bringSubviewToFront:self.generatorView];
        [self.canvasLabel setText:@"Generators"];
        [self transitionToInterfaceState:ZSToolbarInterfaceStateGenerators];
    }
    else {
        self.canvasView.alpha = 0;
        self.canvasView.hidden = NO;
        [self.view bringSubviewToFront:self.canvasView];
        [self.canvasLabel setText:@"Canvas"];
        [self transitionToInterfaceState:ZSToolbarInterfaceStateNormal];
    }
    [self.view bringSubviewToFront:self.canvasLabel];
    self.canvasLabel.alpha = 0;
    self.canvasLabel.hidden = NO;
    
    // Animation
    [UIView animateWithDuration:0.25 animations:^{
        self.canvasLabel.alpha = 100;
        if (generatorHidden) {
            self.generatorView.alpha = 100;
        }
        else {
            self.canvasView.alpha = 100;
        }
    } completion:^(BOOL finished){
        if (!generatorHidden) {
            self.generatorView.hidden = YES;
        }
        [UIView animateWithDuration:0.25 animations:^{
            self.canvasLabel.alpha = 0;
        } completion:^(BOOL finished) {
            self.canvasLabel.hidden = YES;
        }];
    }];
}

- (void)toggleSliderViewWithHandler:(void (^)())handler {
    if (self.gridSliderShowing) {
        [self hideSliderWithHandler:handler];
    }
    else {
        [self showSliderWithHandler:handler];
    }
}

- (void)toggleSubmenuViewWithHandler:(void (^)())handler {
    if (self.submenuShowing) {
        [self hideSubmenuWithHandler:handler];
    }
    else {
        [self showSubmenuWithHandler:handler];
    }
}

- (void)showSliderWithHandler:(void (^)())handler {
    if (self.submenuShowing) {
        [self hideSubmenuWithHandler:nil];
    }
    if (!self.gridSliderShowing) {
        [self.view bringSubviewToFront:self.gridSlider];
        [self.view bringSubviewToFront:self.toolbar];
        CGRect frame = self.gridSlider.frame;
        self.gridSliderShowing = YES;
        frame.origin.y -= frame.size.height;
        [UIView animateWithDuration:0.25 animations:^{
            self.gridSlider.frame = frame;
        } completion:^(BOOL finished) {
            if (handler) {
                handler();
            }
        }];
    }
    else {
        if (handler) {
            handler();
        }
    }
}

- (void)hideSliderWithHandler:(void (^)())handler {
    if (self.gridSliderShowing) {
        [self.view bringSubviewToFront:self.toolbar];
        CGRect frame = self.gridSlider.frame;
        self.gridSliderShowing = NO;
        frame.origin.y += frame.size.height;
        [UIView animateWithDuration:0.25 animations:^{
            self.gridSlider.frame = frame;
        } completion:^(BOOL finished) {
            if (handler) {
                handler();
            }
        }];
    }
    else {
        if (handler) {
            handler();
        }
    }
}
                          
- (void)showSubmenuWithHandler:(void (^)())handler {
    if (self.gridSliderShowing) {
        [self hideSliderWithHandler:nil];
    }
    if (!self.submenuShowing) {
        [self.view bringSubviewToFront:self.submenu];
        [self.view bringSubviewToFront:self.toolbar];
        CGRect frame = self.submenu.frame;
        self.submenuShowing = YES;
        frame.origin.y -= frame.size.height;
        [UIView animateWithDuration:0.25 animations:^{
            self.submenu.frame = frame;
        } completion:^(BOOL finished) {
            if (handler) {
                handler();
            }
        }];
    }
    else {
        if (handler) {
            handler();
        }
    }
}
                          
- (void)hideSubmenuWithHandler:(void (^)())handler {
    if (self.submenuShowing) {
        [self.view bringSubviewToFront:self.toolbar];
        CGRect frame = self.submenu.frame;
        self.submenuShowing = NO;
        frame.origin.y += frame.size.height;
        [UIView animateWithDuration:0.25 animations:^{
            self.submenu.frame = frame;
        } completion:^(BOOL finished) {
            if (handler) {
                handler();
            }
        }];
    }
    else {
        if (handler) {
            handler();
        }
    }
}

- (void)modifyGroups {
    self.groupsController = [[ZSGroupsViewController alloc] init];
    self.groupsController.sprites    = _project.assembledJSON[@"objects"];
    self.groupsController.generators = _project.assembledJSON[@"generators"];
    self.groupsController.groups     = _project.assembledJSON[ZSProjectJSONKeyGroups];
    
    WeakSelf
    self.groupsController.viewControllerNeedsPresented = ^(UIViewController *controller) {
        [weakSelf presentViewController:controller
                           animated:YES
                         completion:^{ }];
    };
    
    self.groupsController.viewControllerNeedsDismissal = ^(UIViewController *controller) {
        [weakSelf dismissViewControllerAnimated:YES
                                     completion:^{}];
    };
    
    self.groupsController.didFinish = ^{
        if (weakSelf.generatorView.hidden) {
            [weakSelf transitionToInterfaceState:ZSToolbarInterfaceStateNormal];
        }
        else {
            [weakSelf transitionToInterfaceState:ZSToolbarInterfaceStateGenerators];
        }
        [UIView animateWithDuration:0.2
                         animations:^{
                             weakSelf.groupsController.view.alpha = 0.0;
                         } completion:^(BOOL finished) {
                             [weakSelf.groupsController.view removeFromSuperview];
                             [weakSelf.groupsController removeFromParentViewController];
                             weakSelf.groupsController = nil;
                         }];
    };
    
    [self transitionToInterfaceState:ZSToolbarInterfaceStateGroups];
    
    self.groupsController.view.frame = self.canvasView.bounds;
    self.groupsController.view.backgroundColor = [UIColor whiteColor];
    if (self.generatorView.hidden) {
        self.groupsController.interfaceState = ZSGroupsInterfaceStateCanvas;
    } else {
        self.groupsController.interfaceState = ZSGroupsInterfaceStateGenerators;
    }
    [self.view addSubview:self.groupsController.view];
}

- (void)finish {
    [self hideSliderWithHandler:^{
        self.canvasView.grid.dimensions = CGSizeMake(0, 0);
        [self.canvasView setNeedsDisplay];
        [self saveProject];
        [self animateCanvasViewOut];
    }];
}

- (void)shareProjectWithCompletion:(void (^)(NSString *URL))completion {
    //    NSURL *baseURL = [NSURL URLWithString:@"http://128.110.74.238:3000/api/v1/"];
    [SVProgressHUD setBackgroundColor:[UIColor zuseBackgroundGrey]];
    [SVProgressHUD setForegroundColor:[UIColor zuseYellow]];
    [SVProgressHUD showWithMaskType:SVProgressHUDMaskTypeClear];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSURL *baseURL = [NSURL URLWithString:@"http://zusehub.com/api/v1/"];
        AFHTTPRequestOperationManager *manager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:baseURL];
        manager.requestSerializer = [AFJSONRequestSerializer serializer];
        manager.responseSerializer = [AFJSONResponseSerializer serializer];

        NSData *projectData = [NSJSONSerialization dataWithJSONObject:self.project.assembledJSON
                                                              options:0
                                                                error:nil];


        NSString *projectString = [[NSString alloc] initWithBytes:projectData.bytes
                                                           length:projectData.length
                                                         encoding:NSUTF8StringEncoding];


        ZSCompiler *compiler = [ZSCompiler compilerWithProjectJSON:self.project.assembledJSON
                                                           options:ZSCompilerOptionWrapInStartEvent];

        NSData *compiledData = [NSJSONSerialization dataWithJSONObject:compiler.compiledComponents
                                                               options:0
                                                                 error:nil];

        NSString *compiledString = [[NSString alloc] initWithBytes:compiledData.bytes
                                                            length:compiledData.length
                                                          encoding:NSUTF8StringEncoding];

        NSDictionary *params = @{
                                 @"shared_project": @{
                                         @"title": self.project.title,
                                         @"project_json": projectString,
                                         @"compiled_components": compiledString
                                         }
                                 };

        NSLog(@"Requesting...");


        [manager POST:@"shared_projects"
           parameters:params
              success:^(AFHTTPRequestOperation *operation, NSDictionary *project) {
                  NSLog(@"Success! %@", project);
                  dispatch_async(dispatch_get_main_queue(), ^{
                      [SVProgressHUD dismiss];
                      completion(project[@"url"]);
                  });
              } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                  dispatch_async(dispatch_get_main_queue(), ^{
                      [SVProgressHUD dismiss];
                  });
                  NSLog(@"Failed! %@", error.localizedDescription);
              }];
        
    });
}

- (void)showToolbox {
    [_toolboxView showAnimated:YES];
}

@end
