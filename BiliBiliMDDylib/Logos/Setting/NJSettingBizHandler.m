//
//  NJSettingBizHandler.m
//  BiliBiliTweak
//
//  Created by touchWorld on 2025/12/28.
//

#import "NJSettingBizHandler.h"
#import "NJSettingDefine.h"
#import "NJSettingInjectDataProvider.h"
#import "NJCommonDefine.h"
#import "UIApplication+NJCategory.h"
#import "NJInlineSettingViewController.h"
#import "NJChangePlaybackRateTool.h"
#import "NJSettingCache.h"
#import "NJCacheCleaner.h"
#import "SVProgressHUD.h"

// 官网地址
#define NJ_OFFICIAL_WEBSITE_URL_STR @"https://github.com/TouchFriend/BiliBiliMApp"

@interface NJSettingBizHandler ()

/// 数据提供者
@property (nonatomic, strong) NJSettingInjectDataProvider *dataProvider;
/// 是否提示过重启
@property (nonatomic, assign) BOOL isRebootTip;


@end

@implementation NJSettingBizHandler

#pragma mark - Life Cycle Methods

- (instancetype)initWithSettingViewController:(UIViewController *)settingViewController tableView:(UITableView *)tableView {
    self = [super init];
    if (self) {
        self.settingViewController = settingViewController;
        self.tableView = tableView;
        [self doInit];
    }
    return self;
}

#pragma mark - Do Init

- (void)doInit {
    self.shareManager = [[NJShareManager alloc] init];
    [self initEventManager];
    self.dataProvider = [[NJSettingInjectDataProvider alloc] init];
    self.injectDatas = self.dataProvider.injectDatas;
    self.isRebootTip = NO;
    [self refreshCacheSize];
}

- (void)initEventManager {
    self.eventManager = [[NJSettingEventManager alloc] init];
    __weak typeof(self) weakSelf = self;
    self.eventManager.aSwitchChange = ^(UISwitch * _Nonnull aSwitch, NJSettingSwitchViewModel * _Nonnull viewModel) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf aSwitchChange:aSwitch
                        viewModel:viewModel];
    };
}

#pragma mark - Override Methods

#pragma mark - Public Methods

- (void)handleBizWithViewModel:(NJSettingSkullViewModel *)viewModel {
    NSString *bizId = viewModel.bizId;
    // 一键清理缓存
    if ([bizId isEqualToString:NJ_CLEAR_CACHE_BIZ_ID]) {
        [self handleClearCacheWithViewModel:viewModel];
        return;
    }
    // 分享数据
    if ([bizId isEqualToString:NJ_SHARE_DATA_BIZ_ID]) {
        [self.shareManager shareCacheFolder];
        return;
    }
    // 官网
    if ([bizId isEqualToString:NJ_OFFICIAL_WEBSITE_BIZ_ID]) {
        NSURL *url = [NSURL URLWithString:NJ_OFFICIAL_WEBSITE_URL_STR];
        [[UIApplication sharedApplication] openURL:url
                                           options:@{}
                                 completionHandler:nil];
        return;
    }
    // 默认播放速度
    if ([bizId isEqualToString:NJ_DEFAULT_PLAYBACK_RATE]) {
        [self handleDefaultPlaybackRateWithViewModel:viewModel];
        return;
    }
    // 关注的默认版块
    if ([bizId isEqualToString:NJ_FOLLOW_DEFAULT_TAB]) {
        [self handleFollowDefaultTabWithViewModel:viewModel];
        return;
    }
}

#pragma mark - Private Methods

/// 一键清理缓存对应的 viewModel
- (nullable NJSettingSkullViewModel *)clearCacheViewModel {
    for (NJSettingSkullViewModel *model in self.injectDatas) {
        if ([model.bizId isEqualToString:NJ_CLEAR_CACHE_BIZ_ID]) {
            return model;
        }
    }
    return nil;
}

/// 异步统计缓存大小并刷新副标题
- (void)refreshCacheSize {
    __weak typeof(self) weakSelf = self;
    [NJCacheCleaner calculateCacheSizeWithCompletion:^(unsigned long long size) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf clearCacheViewModel].subTitle = [NJCacheCleaner formattedSize:size];
        [strongSelf.tableView reloadData];
    }];
}

/// 点击一键清理缓存：先确认，再后台清理并汇报释放大小。
/// 离线下载、账号与插件设置不在清理范围内（见 NJCacheCleaner 白名单）。
- (void)handleClearCacheWithViewModel:(NJSettingSkullViewModel *)viewModel {
    NSString *currentSize = viewModel.subTitle.length > 0 ? viewModel.subTitle : @"计算中…";
    NSString *message = [NSString stringWithFormat:
                         @"当前缓存 %@，清理后图片等内容需重新加载。\n离线下载、账号和设置不会受影响。", currentSize];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清理缓存"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清理"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction * _Nonnull action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [SVProgressHUD showWithStatus:@"正在清理…"];
        [NJCacheCleaner clearCacheWithCompletion:^(unsigned long long freedSize,
                                                     unsigned long long remainingSize) {
            if (freedSize > 0) {
                [SVProgressHUD showSuccessWithStatus:
                    [NSString stringWithFormat:@"已清理 %@", [NJCacheCleaner formattedSize:freedSize]]];
            } else {
                [SVProgressHUD showSuccessWithStatus:@"已是干净状态"];
            }
            viewModel.subTitle = [NJCacheCleaner formattedSize:remainingSize];
            [strongSelf.tableView reloadData];
        }];
    }]];
    [self.settingViewController presentViewController:alert animated:YES completion:nil];
}

/// 点击默认播放速度
/// - Parameter viewModel: 数据
- (void)handleDefaultPlaybackRateWithViewModel:(NJSettingSkullViewModel *)viewModel {
    NSString *selectedValue = viewModel.subTitle;
    NSMutableArray<NJInlineSettingModel *> *dataSource = [NSMutableArray array];
    NSArray<NSString *> *oldPlaybackRates = [NJChangePlaybackRateTool currentPlaybackRates];
    for (NSString *rate in oldPlaybackRates) {
        BOOL selected = rate.doubleValue == selectedValue.doubleValue;
        NJInlineSettingModel *model = [[NJInlineSettingModel alloc] initWithTitle:rate bizId:rate selected:selected];
        [dataSource addObject:model];
    }
    
    NJInlineSettingViewController *inlineVC = [[NJInlineSettingViewController alloc] initWithStyle:UITableViewStylePlain title:@"默认播放速度" dataSource:[dataSource copy]];
    __weak typeof(self) weakSelf = self;
    inlineVC.selectedHandler = ^(NJInlineSettingModel * _Nonnull model) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleChangeDefaultPlaybackRate:model viewModel:viewModel];
    };
    [self.settingViewController.navigationController pushViewController:inlineVC animated:YES];
}

- (void)handleChangeDefaultPlaybackRate:(NJInlineSettingModel *)model viewModel:(NJSettingSkullViewModel *)viewModel {
    NSString *rate = model.title;
    viewModel.subTitle = rate;
    // 保存
    [[NJSettingCache sharedInstance] saveDefaultPlaybackRate:rate];
    [self.tableView reloadData];
}

/// 点击关注的默认版块
/// - Parameter viewModel: 数据
- (void)handleFollowDefaultTabWithViewModel:(NJSettingSkullViewModel *)viewModel {
    NSString *subTitle = viewModel.subTitle;
    NSArray<NJInlineSettingModel *> *followTabs = [self.dataProvider followTabs];
    for (NJInlineSettingModel *model in followTabs) {
        model.selected = [model.title isEqualToString:subTitle];
    }
    
    NJInlineSettingViewController *inlineVC = [[NJInlineSettingViewController alloc] initWithStyle:UITableViewStylePlain title:@"关注页的默认版块" dataSource:followTabs];
    __weak typeof(self) weakSelf = self;
    inlineVC.selectedHandler = ^(NJInlineSettingModel * _Nonnull model) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleChangeFollowDefaultTab:model viewModel:viewModel];
    };
    [self.settingViewController.navigationController pushViewController:inlineVC animated:YES];
}

- (void)handleChangeFollowDefaultTab:(NJInlineSettingModel *)model viewModel:(NJSettingSkullViewModel *)viewModel {
    [self rebootTip];
    viewModel.subTitle = model.title;
    // 保存
    [[NJSettingCache sharedInstance] saveFollowDefaultTab:model.bizId];
    [self.tableView reloadData];
}

- (void)aSwitchChange:(UISwitch *)aSwitch
            viewModel:(NJSettingSwitchViewModel *)viewModel {
    NSString *saveKey = viewModel.saveKey;
    [NJ_SETTING_CACHE setObject:@(viewModel.on) forKey:saveKey];
    [self rebootTip];
}

// 重启提示
- (void)rebootTip {
    if (self.isRebootTip) {
        return;
    }
    self.isRebootTip = YES;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重启应用生效"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [self.settingViewController presentViewController:alert animated:YES completion:^{
        // 当弹窗展示完成后，延迟2秒再自动关闭
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

#pragma mark - Property Methods


@end
