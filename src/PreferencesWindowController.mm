#import "PreferencesWindowController.h"
#import "NextWordPredictor.h"

extern NSUserDefaults *preference;

@interface PreferencesWindowController () <NSWindowDelegate>
@property (nonatomic, strong) NSButton *showTranslationCheckbox;
@property (nonatomic, strong) NSButton *commitWithSpaceCheckbox;
@property (nonatomic, strong) NSButton *enablePredictionCheckbox;
@property (nonatomic, strong) NSPopUpButton *modelTierPopup;
@property (nonatomic, strong) NSButton *downloadModelButton;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTimer *statusTimer;
@end

@implementation PreferencesWindowController

+ (instancetype)shared {
    static PreferencesWindowController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[PreferencesWindowController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 420, 430)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Typeflow Preferences";
    window.level = NSFloatingWindowLevel;
    window.delegate = self;
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        [self setupUI];
        [self loadPreferences];
    }
    return self;
}

- (void)setupUI {
    NSView *content = self.window.contentView;
    CGFloat y = 380;
    CGFloat leftMargin = 30;

    // --- Input Settings Section ---
    NSTextField *inputHeader = [self createLabel:@"Input Settings" bold:YES];
    inputHeader.frame = NSMakeRect(leftMargin, y, 360, 20);
    [content addSubview:inputHeader];
    y -= 8;

    NSBox *separator1 = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y, 360, 1)];
    separator1.boxType = NSBoxSeparator;
    [content addSubview:separator1];
    y -= 30;

    _showTranslationCheckbox = [NSButton checkboxWithTitle:@"Show Translation"
                                                    target:self
                                                    action:@selector(preferencesChanged:)];
    _showTranslationCheckbox.frame = NSMakeRect(leftMargin, y, 360, 20);
    [content addSubview:_showTranslationCheckbox];
    y -= 28;

    _commitWithSpaceCheckbox = [NSButton checkboxWithTitle:@"Commit word with space"
                                                    target:self
                                                    action:@selector(preferencesChanged:)];
    _commitWithSpaceCheckbox.frame = NSMakeRect(leftMargin, y, 360, 20);
    [content addSubview:_commitWithSpaceCheckbox];
    y -= 40;

    // --- Prediction Settings Section ---
    NSTextField *predHeader = [self createLabel:@"Next Word Prediction (LLM)" bold:YES];
    predHeader.frame = NSMakeRect(leftMargin, y, 360, 20);
    [content addSubview:predHeader];
    y -= 8;

    NSBox *separator2 = [[NSBox alloc] initWithFrame:NSMakeRect(leftMargin, y, 360, 1)];
    separator2.boxType = NSBoxSeparator;
    [content addSubview:separator2];
    y -= 30;

    _enablePredictionCheckbox = [NSButton checkboxWithTitle:@"Enable next-word prediction"
                                                    target:self
                                                    action:@selector(predictionToggled:)];
    _enablePredictionCheckbox.frame = NSMakeRect(leftMargin, y, 360, 20);
    [content addSubview:_enablePredictionCheckbox];
    y -= 32;

    NSTextField *modelLabel = [self createLabel:@"Model size:" bold:NO];
    modelLabel.frame = NSMakeRect(leftMargin, y, 80, 20);
    [content addSubview:modelLabel];

    _modelTierPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(leftMargin + 85, y - 2, 275, 26) pullsDown:NO];
    [_modelTierPopup addItemWithTitle:@"Small - smollm-135m-q8_0.gguf"];
    [_modelTierPopup addItemWithTitle:@"Medium - qwen2-0.5b-q8_0.gguf"];
    [_modelTierPopup addItemWithTitle:@"Large - qwen2-1.5b-q4_k_m.gguf"];
    [_modelTierPopup addItemWithTitle:@"XLarge - qwen2.5-3b-q4_k_m.gguf"];
    [_modelTierPopup setTarget:self];
    [_modelTierPopup setAction:@selector(modelTierChanged:)];
    [content addSubview:_modelTierPopup];
    y -= 40;

    _downloadModelButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 180, 24)];
    _downloadModelButton.title = @"Download Selected Model";
    _downloadModelButton.bezelStyle = NSBezelStyleRounded;
    _downloadModelButton.controlSize = NSControlSizeSmall;
    _downloadModelButton.font = [NSFont systemFontOfSize:11];
    [_downloadModelButton setTarget:self];
    [_downloadModelButton setAction:@selector(downloadSelectedModel:)];
    [content addSubview:_downloadModelButton];
    y -= 34;

    [self updateModelAvailability];
    y -= 6;

    // --- Status ---
    _statusLabel = [self createLabel:@"" bold:NO];
    _statusLabel.frame = NSMakeRect(leftMargin, y, 360, 36);
    _statusLabel.maximumNumberOfLines = 2;
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.font = [NSFont systemFontOfSize:11];
    [content addSubview:_statusLabel];
    y -= 40;

    // --- Open Models Folder Button ---
    NSButton *openFolderButton = [[NSButton alloc] initWithFrame:NSMakeRect(leftMargin, y, 180, 24)];
    openFolderButton.title = @"Open Models Folder";
    openFolderButton.bezelStyle = NSBezelStyleRounded;
    openFolderButton.controlSize = NSControlSizeSmall;
    openFolderButton.font = [NSFont systemFontOfSize:11];
    [openFolderButton setTarget:self];
    [openFolderButton setAction:@selector(openModelsFolder:)];
    [content addSubview:openFolderButton];

    // --- Apply Button ---
    NSButton *applyButton = [[NSButton alloc] initWithFrame:NSMakeRect(280, 15, 110, 32)];
    applyButton.title = @"Apply";
    applyButton.bezelStyle = NSBezelStyleRounded;
    applyButton.keyEquivalent = @"\r";
    [applyButton setTarget:self];
    [applyButton setAction:@selector(applyPreferences:)];
    [content addSubview:applyButton];
}

- (NSTextField *)createLabel:(NSString *)text bold:(BOOL)bold {
    NSTextField *label = [NSTextField labelWithString:text];
    label.editable = NO;
    label.bordered = NO;
    label.backgroundColor = [NSColor clearColor];
    if (bold) {
        label.font = [NSFont boldSystemFontOfSize:13];
    }
    return label;
}

- (void)loadPreferences {
    _showTranslationCheckbox.state = [preference boolForKey:@"showTranslation"] ? NSControlStateValueOn : NSControlStateValueOff;
    _commitWithSpaceCheckbox.state = [preference boolForKey:@"commitWordWithSpace"] ? NSControlStateValueOn : NSControlStateValueOff;
    _enablePredictionCheckbox.state = [preference boolForKey:@"enableNextWordPrediction"] ? NSControlStateValueOn : NSControlStateValueOff;

    NSInteger tier = [preference integerForKey:@"modelTier"];
    if (tier >= 0 && tier < _modelTierPopup.numberOfItems) {
        [_modelTierPopup selectItemAtIndex:tier];
    }

    [self refreshModelUI];
    [self updateModelTierEnabled];
}

- (void)updateModelAvailability {
    NSArray<NSString *> *baseTitles = @[
        @"Small - smollm-135m-q8_0.gguf",
        @"Medium - qwen2-0.5b-q8_0.gguf",
        @"Large - qwen2-1.5b-q4_k_m.gguf",
        @"XLarge - qwen2.5-3b-q4_k_m.gguf"
    ];

    for (NSInteger tier = 0; tier < baseTitles.count; tier++) {
        BOOL available = [NextWordPredictor isModelAvailableForTier:(LLMModelTier)tier];
        NSMenuItem *item = [_modelTierPopup itemAtIndex:tier];
        item.title = available ? baseTitles[tier] : [baseTitles[tier] stringByAppendingString:@" (not downloaded)"];
        item.enabled = YES;
    }
}

- (void)updateModelTierEnabled {
    BOOL predictionEnabled = _enablePredictionCheckbox.state == NSControlStateValueOn;
    _modelTierPopup.enabled = predictionEnabled;
}

- (NSString *)tierNameForTier:(LLMModelTier)tier {
    NSArray<NSString *> *tierNames = @[ @"Small", @"Medium", @"Large", @"XLarge" ];
    if (tier >= 0 && tier < tierNames.count) {
        return tierNames[tier];
    }
    return @"Unknown";
}

- (void)updateDownloadControls {
    NextWordPredictor *predictor = [NextWordPredictor shared];
    NSInteger selectedTier = _modelTierPopup.indexOfSelectedItem;
    BOOL selectedTierAvailable = [NextWordPredictor isModelAvailableForTier:(LLMModelTier)selectedTier];

    if (predictor.isDownloadingModel) {
        _downloadModelButton.enabled = NO;
        _downloadModelButton.title = [NSString stringWithFormat:@"Downloading %@...",
                                                                [self tierNameForTier:predictor.downloadingTier]];
        return;
    }

    _downloadModelButton.enabled = !selectedTierAvailable;
    _downloadModelButton.title = selectedTierAvailable ? @"Model Already Downloaded" : @"Download Selected Model";
}

- (void)updateStatus {
    NextWordPredictor *predictor = [NextWordPredictor shared];
    NSString *modelsDir = [NextWordPredictor modelDirectoryPath];
    NSInteger selectedTier = _modelTierPopup.indexOfSelectedItem;

    if (predictor.isDownloadingModel) {
        _statusLabel.textColor = [NSColor systemOrangeColor];
        NSInteger percent = (NSInteger)llround(predictor.downloadProgress * 100.0);
        NSString *message = predictor.downloadStatus ?: @"Downloading model...";
        _statusLabel.stringValue = [NSString stringWithFormat:@"%@\n%ld%% complete • %@", message, (long)percent, modelsDir];
    } else if (predictor.isModelLoaded) {
        NSString *tierName = [self tierNameForTier:predictor.currentTier];
        _statusLabel.textColor = [NSColor colorWithRed:0.2 green:0.6 blue:0.3 alpha:1.0];
        _statusLabel.stringValue = [NSString stringWithFormat:@"Model loaded (%@)\nModel directory: %@", tierName, modelsDir];
    } else if (![NextWordPredictor isModelAvailableForTier:(LLMModelTier)selectedTier]) {
        _statusLabel.textColor = [NSColor systemOrangeColor];
        _statusLabel.stringValue = [NSString stringWithFormat:@"%@ model is not downloaded yet.\nModel directory: %@",
                                                              [self tierNameForTier:(LLMModelTier)selectedTier], modelsDir];
    } else {
        _statusLabel.textColor = [NSColor secondaryLabelColor];
        _statusLabel.stringValue = [NSString stringWithFormat:@"Model not loaded\nModel directory: %@", modelsDir];
    }
}

- (void)refreshModelUI {
    [self updateModelAvailability];
    [self updateDownloadControls];
    [self updateStatus];
}

- (void)startStatusTimer {
    if (self.statusTimer) {
        return;
    }

    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.75
                                                        target:self
                                                      selector:@selector(handleStatusTimer:)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)stopStatusTimer {
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}

- (void)handleStatusTimer:(NSTimer *)timer {
    [self refreshModelUI];
    if (![NextWordPredictor shared].isDownloadingModel) {
        [self stopStatusTimer];
    }
}

#pragma mark - Actions

- (void)preferencesChanged:(id)sender {
    // Immediate save for checkboxes
}

- (void)predictionToggled:(id)sender {
    [self updateModelTierEnabled];
    [self updateDownloadControls];
}

- (void)modelTierChanged:(id)sender {
    [self refreshModelUI];
}

- (void)openModelsFolder:(id)sender {
    NSString *modelsDir = [NSString stringWithFormat:@"%@/Library/Application Support/Typeflow/models",
                           NSHomeDirectory()];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:modelsDir]) {
        [fm createDirectoryAtPath:modelsDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:modelsDir]];
}

- (void)applyPreferences:(id)sender {
    [preference setBool:(_showTranslationCheckbox.state == NSControlStateValueOn) forKey:@"showTranslation"];
    [preference setBool:(_commitWithSpaceCheckbox.state == NSControlStateValueOn) forKey:@"commitWordWithSpace"];

    BOOL enablePrediction = _enablePredictionCheckbox.state == NSControlStateValueOn;
    BOOL wasEnabled = [preference boolForKey:@"enableNextWordPrediction"];
    [preference setBool:enablePrediction forKey:@"enableNextWordPrediction"];

    NSInteger newTier = [_modelTierPopup indexOfSelectedItem];
    NSInteger oldTier = [preference integerForKey:@"modelTier"];
    [preference setInteger:newTier forKey:@"modelTier"];

    [preference synchronize];

    // Handle model loading/unloading
    if (!enablePrediction && wasEnabled) {
        [[NextWordPredictor shared] unloadModel];
    } else if (enablePrediction && ![NextWordPredictor isModelAvailableForTier:(LLMModelTier)newTier]) {
        _statusLabel.textColor = [NSColor systemOrangeColor];
        _statusLabel.stringValue = [NSString stringWithFormat:@"%@ model is not downloaded yet.\nUse the download button first.",
                                                              [self tierNameForTier:(LLMModelTier)newTier]];
        [self updateDownloadControls];
        return;
    } else if (enablePrediction && (newTier != oldTier || !wasEnabled)) {
        _statusLabel.textColor = [NSColor systemOrangeColor];
        _statusLabel.stringValue = @"Loading model...";

        [[NextWordPredictor shared] loadModelForTier:(LLMModelTier)newTier completion:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    [self updateStatus];
                } else {
                    self->_statusLabel.textColor = [NSColor systemRedColor];
                    self->_statusLabel.stringValue = [NSString stringWithFormat:@"Failed to load model: %@",
                                                      error.localizedDescription];
                }
            });
        }];
        return;
    }

    [self refreshModelUI];
}

- (void)downloadSelectedModel:(id)sender {
    NSInteger selectedTier = _modelTierPopup.indexOfSelectedItem;
    NSError *error = nil;
    BOOL started = [[NextWordPredictor shared] downloadModelForTier:(LLMModelTier)selectedTier
                                                              error:&error
                                                         completion:^(BOOL success, NSError *completionError) {
                                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                                 if (success &&
                                                                     [preference boolForKey:@"enableNextWordPrediction"] &&
                                                                     [preference integerForKey:@"modelTier"] == selectedTier) {
                                                                     self->_statusLabel.textColor = [NSColor systemOrangeColor];
                                                                     self->_statusLabel.stringValue = @"Loading downloaded model...";
                                                                     [[NextWordPredictor shared] loadModelForTier:(LLMModelTier)selectedTier completion:^(BOOL loadSuccess, NSError *loadError) {
                                                                         dispatch_async(dispatch_get_main_queue(), ^{
                                                                             if (!loadSuccess) {
                                                                                 self->_statusLabel.textColor = [NSColor systemRedColor];
                                                                                 self->_statusLabel.stringValue = [NSString stringWithFormat:@"Downloaded, but failed to load: %@",
                                                                                                                   loadError.localizedDescription];
                                                                             }
                                                                             [self refreshModelUI];
                                                                         });
                                                                     }];
                                                                     return;
                                                                 }

                                                                 if (!success && completionError) {
                                                                     self->_statusLabel.textColor = [NSColor systemRedColor];
                                                                     self->_statusLabel.stringValue = [NSString stringWithFormat:@"Download failed: %@",
                                                                                                       completionError.localizedDescription];
                                                                 }
                                                                 [self refreshModelUI];
                                                             });
                                                         }];

    if (!started) {
        _statusLabel.textColor = [NSColor systemRedColor];
        _statusLabel.stringValue = [NSString stringWithFormat:@"Could not start download: %@",
                                                              error.localizedDescription ?: @"Unknown error"];
        return;
    }

    [self refreshModelUI];
    [self startStatusTimer];
}

- (void)showWindow {
    [self loadPreferences];
    [self refreshModelUI];
    if ([NextWordPredictor shared].isDownloadingModel) {
        [self startStatusTimer];
    }
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self stopStatusTimer];
}

@end
