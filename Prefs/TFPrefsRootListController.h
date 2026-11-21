#import <UIKit/UIKit.h>

@interface TFPrefsRootListController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray *sections;
@end

@interface TFAdvancedController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (UITableView *)table;
@end
