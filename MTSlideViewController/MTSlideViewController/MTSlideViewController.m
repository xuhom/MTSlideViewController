#import "MTSlideViewController.h"
#import "MTSlideViewTableViewCell.h"
#import <QuartzCore/QuartzCore.h>

/** Point at which panel slides out if moved from left */
#define kMTLeftSlideDecisionPointX                  100.f
/** Point at which panel slides in if moved from right */
#define kMTRightSlideDecisionPointX                 265.f
/** Position where panel starts when slided out */
#define kMTRightAnchorX                             270.f
/** Minimum velocity to recognize a pan as a quick flip */
#define kMTMinimumVelocityToTriggerSlide            1000.f
#define kMTSlideAnimationDuration                   0.2


@interface MTSlideViewController () <UITableViewDelegate, UITableViewDataSource, UINavigationControllerDelegate, UISearchBarDelegate, UITextFieldDelegate> {
    BOOL rotationEnabled_;
    CGPoint startingDragPoint_;
    CGFloat startingDragTransformTx_;
    UITapGestureRecognizer *tableViewTapGestureRecognizer_;
    UITapGestureRecognizer *slideInTapGestureRecognizer_;
}

@property (nonatomic, strong, readwrite) UINavigationController *slideNavigationController;
@property (nonatomic, strong, readwrite) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIImageView *searchBarBackgroundView;

- (void)configureViewController:(UIViewController *)viewController;
- (void)menuBarButtonItemPressed:(id)sender;

- (void)handlePan:(UIPanGestureRecognizer *)gestureRecognizer;
- (void)handleSlideInTap:(UITapGestureRecognizer *)gestureRecognizer;
- (void)handleTableViewTap:(UITapGestureRecognizer *)gestureRecognizer;

- (void)handleTouchesBeganAtLocation:(CGPoint)location;
- (void)handleTouchesMovedToLocation:(CGPoint)location;
- (void)handleTouchesEndedAtLocation:(CGPoint)location;

@end

@implementation MTSlideViewController

@synthesize slideNavigationController = slideNavigationController_;
@synthesize searchBar = searchBar_;
@synthesize searchBarBackgroundView = searchBarBackgroundView_;
@synthesize tableView = tableView_;
@synthesize slideState = slideState_;
@synthesize delegate = delegate_;
@synthesize dataSource = dataSource_;
@synthesize slideMode = slideMode_;

////////////////////////////////////////////////////////////////////////
#pragma mark - Lifecycle
////////////////////////////////////////////////////////////////////////

+ (MTSlideViewController *)slideViewController {
    return [[[self class] alloc] initWithNibName:nil bundle:nil];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nil])) {
        rotationEnabled_ = YES;
        slideMode_ = MTSlideViewControllerModeAllViewController | MTSlideViewControllerModeWholeView;
        slideState_ = MTSlideViewControllerStateNormal;
    }
    
    return self;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - UIViewController
////////////////////////////////////////////////////////////////////////

- (void)viewDidLoad {
    [super viewDidLoad];
    
    searchBarBackgroundView_ = [[UIImageView alloc] initWithFrame:CGRectMake(0.f, 0.f, 320.f, 44.f)];
    searchBarBackgroundView_.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:searchBarBackgroundView_];
    
    searchBar_ = [[UISearchBar alloc] initWithFrame:CGRectMake(0.f, 0.f, kMTRightAnchorX, 44.f)];
    searchBar_.delegate = self;
    searchBar_.tintColor = [UIColor colorWithRed:36.f/255.f green:43.f/255.f blue:57.f/255.f alpha:1.f];
    [self.view addSubview:searchBar_];
    
    tableView_ = [[UITableView alloc] initWithFrame:CGRectMake(0.f, 44.f, 320.f, self.view.bounds.size.height-44.f) style:UITableViewStylePlain];
    tableView_.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tableView_.backgroundColor = [UIColor colorWithRed:50.f/255.f green:57.f/255.f blue:74.f/255.f alpha:1.f];
    tableView_.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView_.delegate = self;
    tableView_.dataSource = self;
    [self.view addSubview:tableView_];
    
    if (![self.dataSource respondsToSelector:@selector(slideViewController:searchTermDidChange:)] || 
        ![self.dataSource respondsToSelector:@selector(searchDatasourceForSlideViewController:)]) {
        searchBar_.hidden = YES;
        searchBarBackgroundView_.hidden = YES;
        tableView_.frame = CGRectMake(0.0f, 0.0f, 320.0f, self.view.bounds.size.height);
    }
    
    UIViewController *initalViewController = [self.dataSource initialViewControllerForSlideViewController:self];
    [self configureViewController:initalViewController];
    
    slideNavigationController_ = [[UINavigationController alloc] initWithRootViewController:initalViewController];
    slideNavigationController_.delegate = self;
    slideNavigationController_.view.layer.shadowColor = [[UIColor blackColor] CGColor];
    slideNavigationController_.view.layer.shadowOffset = CGSizeMake(0.0f, 0.0f);
    slideNavigationController_.view.layer.shadowRadius = 4.0f;
    slideNavigationController_.view.layer.shadowOpacity = 0.75f;
    [slideNavigationController_ willMoveToParentViewController:self];
    [self addChildViewController:slideNavigationController_];
    [self.view addSubview:slideNavigationController_.view];
    [slideNavigationController_ didMoveToParentViewController:self];
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:slideNavigationController_.view.bounds cornerRadius:4.0];
    slideNavigationController_.view.layer.shadowPath = path.CGPath;
    
    UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [slideNavigationController_.navigationBar addGestureRecognizer:panRecognizer];
    [slideNavigationController_.view addGestureRecognizer:panRecognizer];
    
    slideInTapGestureRecognizer_ = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSlideInTap:)];
    slideInTapGestureRecognizer_.enabled = NO;
    [slideNavigationController_.view addGestureRecognizer:slideInTapGestureRecognizer_];
    
    tableViewTapGestureRecognizer_ = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTableViewTap:)];
    tableViewTapGestureRecognizer_.enabled = NO;
    [self.tableView addGestureRecognizer:tableViewTapGestureRecognizer_];
    
    UIImage *searchBarBackground = [UIImage imageNamed:@"MTSlideViewController.bundle/search_bar_background"];
    [searchBar_ setBackgroundImage:[searchBarBackground stretchableImageWithLeftCapWidth:0 topCapHeight:0]];
    searchBarBackgroundView_.image = [searchBarBackground stretchableImageWithLeftCapWidth:0 topCapHeight:0];
    searchBar_.placeholder = NSLocalizedString(@"Search", @"Search");
    
    if ([self.dataSource respondsToSelector:@selector(initialSelectedIndexPathForSlideViewController:)]) {
        [tableView_ selectRowAtIndexPath:[self.dataSource initialSelectedIndexPathForSlideViewController:self]
                                animated:NO 
                          scrollPosition:UITableViewScrollPositionTop];
    }
}

- (void)viewDidUnload {
    [super viewDidUnload];
    
    self.searchBar = nil;
    self.searchBarBackgroundView = nil;
    self.tableView = nil;
    self.slideNavigationController = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return rotationEnabled_ && toInterfaceOrientation != UIInterfaceOrientationPortraitUpsideDown;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - MTSlideViewController
////////////////////////////////////////////////////////////////////////

- (void)showViewController:(UIViewController *)viewController {
    if (viewController != nil) {
        [self configureViewController:viewController];
        [slideNavigationController_ setViewControllers:[NSArray arrayWithObject:viewController] animated:NO];
        [self slideInSlideNavigationControllerView];
    }
}

- (void)configureViewController:(UIViewController *)viewController {
    UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"MTSlideViewController.bundle/menu_icon"]
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(menuBarButtonItemPressed:)];
    
    viewController.navigationItem.leftBarButtonItem = barButtonItem;
}

- (void)menuBarButtonItemPressed:(id)sender {
    if (slideState_ == MTSlideViewControllerStatePeeking) {
        [self slideInSlideNavigationControllerView];
        return;
    }
    
    UIViewController *currentViewController = [[slideNavigationController_ viewControllers] objectAtIndex:0];
    
    if ([currentViewController conformsToProtocol:@protocol(MTSlideViewControllerSlideDelegate)]
        && [currentViewController respondsToSelector:@selector(shouldSlideOut)]) {
        if ([(id <MTSlideViewControllerSlideDelegate>)currentViewController shouldSlideOut]) {
            [self slideOutSlideNavigationControllerView];
        }
    } else {
        [self slideOutSlideNavigationControllerView];
    }
}

- (void)slideOutSlideNavigationControllerView {
    slideState_ = MTSlideViewControllerStatePeeking;
    slideNavigationController_.topViewController.view.userInteractionEnabled = NO;
    
    [UIView animateWithDuration:kMTSlideAnimationDuration
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState 
                     animations:^{
                         slideNavigationController_.view.transform = CGAffineTransformMakeTranslation(kMTRightAnchorX, 0.f);
                     } completion:^(BOOL finished) {
                         searchBar_.frame = CGRectMake(0.f, 0.f, kMTRightAnchorX, searchBar_.frame.size.height);
                         slideInTapGestureRecognizer_.enabled = YES;
                     }];
}

- (void)slideInSlideNavigationControllerView {
    [UIView animateWithDuration:kMTSlideAnimationDuration 
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         slideNavigationController_.view.transform = CGAffineTransformIdentity;
                     } completion:^(BOOL finished) {
                         slideNavigationController_.topViewController.view.userInteractionEnabled = YES;
                         slideInTapGestureRecognizer_.enabled = NO;
                         [self cancelSearching];
                         slideState_ = MTSlideViewControllerStateNormal;
                     }];
}

- (void)slideSlideNavigationControllerViewOffScreen {
    CGFloat width = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation) ? 480.f : 320.f;
    
    slideState_ = MTSlideViewControllerStateSearching;
    slideInTapGestureRecognizer_.enabled = NO;
    
    [UIView animateWithDuration:kMTSlideAnimationDuration
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState 
                     animations:^{
                         slideNavigationController_.view.transform = CGAffineTransformMakeTranslation(width, 0.0f);
                         searchBar_.frame = CGRectMake(0.f, 0.f, width, searchBar_.frame.size.height);
                     } completion:nil];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - UIGestureRecognizer
////////////////////////////////////////////////////////////////////////

- (void)handlePan:(UIPanGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        [self handleTouchesBeganAtLocation:[gestureRecognizer locationInView:self.view]];
    } else if (gestureRecognizer.state == UIGestureRecognizerStateChanged) {
        [self handleTouchesMovedToLocation:[gestureRecognizer locationInView:self.view]];
    } else if (gestureRecognizer.state == UIGestureRecognizerStateEnded ||
               gestureRecognizer.state == UIGestureRecognizerStateCancelled ||
               gestureRecognizer.state == UIGestureRecognizerStateFailed) {
        CGFloat velocity = [gestureRecognizer velocityInView:self.view].x;
        
        // Quick Flick?
        if (fabs(velocity) > kMTMinimumVelocityToTriggerSlide) {
            if (velocity > 0.f) {
                [self slideOutSlideNavigationControllerView];
            } else {
                [self slideInSlideNavigationControllerView];
            }
        }  else {
            [self handleTouchesEndedAtLocation:[gestureRecognizer locationInView:self.view]];
        }
    }
}

- (void)handleSlideInTap:(UITapGestureRecognizer *)gestureRecognizer {
    if (slideState_ == MTSlideViewControllerStatePeeking) {
        [self slideInSlideNavigationControllerView];
    }
}

- (void)handleTableViewTap:(UITapGestureRecognizer *)gestureRecognizer {
    [searchBar_ resignFirstResponder];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - UINavigationControllerDelegate
////////////////////////////////////////////////////////////////////////

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    [self cancelSearching];
    
    if ([navigationController viewControllers].count > 1) {
        slideState_ = MTSlideViewControllerStateDrilledDown;
    } else {
        slideState_ = MTSlideViewControllerStateNormal;
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - UITableViewDataSource
////////////////////////////////////////////////////////////////////////

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (slideState_ == MTSlideViewControllerStateSearching) {
        return [self.dataSource searchDatasourceForSlideViewController:self].count;
    } else {
        return [[[[self.dataSource datasourceForSlideViewController:self] objectAtIndex:section] objectForKey:kMTSlideViewControllerSectionViewControllersKey] count];        
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (slideState_ == MTSlideViewControllerStateSearching) {
        return 1;
    } else {
        return [self.dataSource datasourceForSlideViewController:self].count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MTSlideViewTableViewCell *cell = [MTSlideViewTableViewCell cellForTableView:tableView style:UITableViewCellStyleDefault ];
    NSDictionary *viewControllerDictionary = nil;
    
    if (slideState_ == MTSlideViewControllerStateSearching) {
        viewControllerDictionary = [[self.dataSource searchDatasourceForSlideViewController:self] objectAtIndex:indexPath.row];
    } else {
        viewControllerDictionary = [[[[self.dataSource datasourceForSlideViewController:self] objectAtIndex:indexPath.section] objectForKey:kMTSlideViewControllerSectionViewControllersKey] objectAtIndex:indexPath.row];
    }
    
    cell.textLabel.text = [viewControllerDictionary objectForKey:kMTSlideViewControllerViewControllerTitleKey];
    
    if ([[viewControllerDictionary objectForKey:kMTSlideViewControllerViewControllerIconKey] isKindOfClass:[UIImage class]]) {
        cell.imageView.image = [viewControllerDictionary objectForKey:kMTSlideViewControllerViewControllerIconKey];
    } else {
        cell.imageView.image = nil;
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (slideState_ == MTSlideViewControllerStateSearching) {
        return nil;
    }
    
    NSDictionary *sectionDictionary = [[self.dataSource datasourceForSlideViewController:self] objectAtIndex:section];
    
    if ([sectionDictionary objectForKey:kMTSlideViewControllerSectionTitleKey]) {
        NSString *sectionTitle = [sectionDictionary objectForKey:kMTSlideViewControllerSectionTitleKey];
        
        if ([sectionTitle isEqualToString:kMTSlideViewControllerSectionTitleNoTitle]) {
            return nil;
        } else {
            return sectionTitle;
        }
    } else {
        return nil;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (slideState_ == MTSlideViewControllerStateSearching) {
        return nil;
    }
    
    NSString *titleString = [self tableView:tableView titleForHeaderInSection:section];
    
    if (titleString == nil) {
        return nil;
    }
    
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0.f, 0.f, tableView.bounds.size.width, 22.f)];
    imageView.image = [[UIImage imageNamed:@"MTSlideViewController.bundle/section_background"] stretchableImageWithLeftCapWidth:0.f topCapHeight:0.f];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectInset(imageView.frame, 10.f, 0.f)];
    titleLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:12.f];
    titleLabel.textAlignment = UITextAlignmentLeft;
    titleLabel.textColor = [UIColor colorWithRed:125.f/255.f green:129.f/255.f blue:146.f/255.f alpha:1.f];
    titleLabel.shadowColor = [UIColor colorWithRed:40.f/255.f green:45.f/255.f blue:57.f/255.f alpha:1.f];
    titleLabel.shadowOffset = CGSizeMake(0.f, 1.f);
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.text = titleString;
    [imageView addSubview:titleLabel];
    
    return imageView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (slideState_ == MTSlideViewControllerStateSearching) {
        return 0.f;
    } else if ([self tableView:tableView titleForHeaderInSection:section]) {
        return 22.f;
    } else {
        return 0.f;
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - UITableViewDelegate
////////////////////////////////////////////////////////////////////////

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *viewControllerDictionary = nil;
    
    if (slideState_ == MTSlideViewControllerStateSearching) {
        viewControllerDictionary = [[self.dataSource searchDatasourceForSlideViewController:self] objectAtIndex:indexPath.row];
    } else {
        viewControllerDictionary = [[[[self.dataSource datasourceForSlideViewController:self] objectAtIndex:indexPath.section] objectForKey:kMTSlideViewControllerSectionViewControllersKey] objectAtIndex:indexPath.row];
    }
    
    id viewController = [viewControllerDictionary objectForKey:kMTSlideViewControllerViewControllerKey];
    
    if ([self.delegate respondsToSelector:@selector(slideViewController:didSelectViewController:atIndexPath:)]) {
        [self.delegate slideViewController:self
                   didSelectViewController:viewController
                               atIndexPath:indexPath];
    }
    
    [self showViewController:viewController];
}

////////////////////////////////////////////////////////////////////////
#pragma mark - UISearchBarDelegate
////////////////////////////////////////////////////////////////////////

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    if ([self.delegate respondsToSelector:@selector(slideViewControllerDidBeginSearching:)]) {
        [self.delegate slideViewControllerDidBeginSearching:self];
    }
    
    if ([self.dataSource respondsToSelector:@selector(slideViewController:searchTermDidChange:)]) {
        [self slideSlideNavigationControllerViewOffScreen];
        [self.dataSource slideViewController:self searchTermDidChange:searchBar.text];
        [tableView_ reloadData];
    }
    
    [searchBar setShowsCancelButton:YES animated:YES];
    rotationEnabled_ = NO;
    tableViewTapGestureRecognizer_.enabled = YES;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if ([self.dataSource respondsToSelector:@selector(slideViewController:searchTermDidChange:)]) {
        [self.dataSource slideViewController:self searchTermDidChange:searchBar.text];
        [tableView_ reloadData];
    }
    
    if (searchText.length == 0) {
        tableViewTapGestureRecognizer_.enabled = YES;
    } else {
        tableViewTapGestureRecognizer_.enabled = NO;
    }
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    rotationEnabled_ = YES;
    tableViewTapGestureRecognizer_.enabled = NO;
    [searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [self cancelSearching];
    [self slideOutSlideNavigationControllerView];
    [tableView_ reloadData];
    
    if ([self.delegate respondsToSelector:@selector(slideViewControllerDidEndSearching:)]) {
        [self.delegate slideViewControllerDidEndSearching:self];
    }
}

- (void)cancelSearching {
    if (slideState_ == MTSlideViewControllerStateSearching) {
        [searchBar_ resignFirstResponder];
        slideState_ = MTSlideViewControllerStateNormal;
        searchBar_.text = @"";
        [tableView_ reloadData];
    }
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Private
////////////////////////////////////////////////////////////////////////

- (void)handleTouchesBeganAtLocation:(CGPoint)location {
    if (!(slideMode_ & MTSlideViewControllerModeAllViewController) &&
        slideState_ == MTSlideViewControllerStateDrilledDown) {
        return;
    }
    
    if (slideState_ == MTSlideViewControllerStateSearching) {
        return;
    }
    
    startingDragPoint_ = location;
    
    if ((CGRectContainsPoint(slideNavigationController_.view.frame, startingDragPoint_)) && 
        slideState_ == MTSlideViewControllerStatePeeking) {
        slideState_ = MTSlideViewControllerStateDragging;
        startingDragTransformTx_ = slideNavigationController_.view.transform.tx;
    }
    
    // we only trigger a swipe if either navigationBarOnly is deactivated
    // or we swiped in the navigationBar
    if (slideMode_ & MTSlideViewControllerModeWholeView || startingDragPoint_.y <= self.slideNavigationController.navigationBar.frame.size.height) {
        slideState_ = MTSlideViewControllerStateDragging;
        startingDragTransformTx_ = slideNavigationController_.view.transform.tx;
    }
}

- (void)handleTouchesMovedToLocation:(CGPoint)location {
    if (slideState_ != MTSlideViewControllerStateDragging) {
        return;
    }
    
    [UIView animateWithDuration:0.05 
                          delay:0.0
                        options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionBeginFromCurrentState 
                     animations:^{
                         slideNavigationController_.view.transform = CGAffineTransformMakeTranslation(MAX(startingDragTransformTx_ + (location.x - startingDragPoint_.x), 0.0f), 0.0f);
                     } completion:nil];
}

- (void)handleTouchesEndedAtLocation:(CGPoint)location {
    if (slideState_ == MTSlideViewControllerStateDragging) {
        // Check in which direction we were dragging
        if (location.x < startingDragPoint_.x) {
            if (slideNavigationController_.view.transform.tx <= kMTRightSlideDecisionPointX) {
                [self slideInSlideNavigationControllerView];
            } else {
                [self slideOutSlideNavigationControllerView]; 
            }
        } else {
            if (slideNavigationController_.view.transform.tx >= kMTLeftSlideDecisionPointX) {
                [self slideOutSlideNavigationControllerView];
            } else {
                [self slideInSlideNavigationControllerView];
            }
        }
    }
}

@end
