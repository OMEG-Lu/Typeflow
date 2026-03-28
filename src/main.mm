#import "ConversionEngine.h"
#import "NextWordPredictor.h"
#import "WebServer.h"
#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <InputMethodKit/InputMethodKit.h>

NSUserDefaults *preference;
ConversionEngine *engine;

const NSString *kConnectionName = @"Typeflow_1_Connection";
IMKCandidates *sharedCandidates;

static const unsigned char kInstallLocation[] = "/Library/Input Methods/Typeflow.app";
static NSString *const kSourceID = @"com.typeflow.inputmethod.TypeflowInputMethod";

void registerInputSource() {
    CFURLRef installedLocationURL =
        CFURLCreateFromFileSystemRepresentation(NULL, kInstallLocation, strlen((const char *)kInstallLocation), NO);
    if (installedLocationURL) {
        TISRegisterInputSource(installedLocationURL);
        CFRelease(installedLocationURL);
        NSLog(@"Registered input source from %s", kInstallLocation);
    }
}

void activateInputSource() {
    CFArrayRef sourceList = TISCreateInputSourceList(NULL, true);
    for (int i = 0; i < CFArrayGetCount(sourceList); ++i) {
        TISInputSourceRef inputSource = (TISInputSourceRef)(CFArrayGetValueAtIndex(sourceList, i));
        NSString *sourceID = (__bridge NSString *)(TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID));
        if ([sourceID isEqualToString:kSourceID]) {
            TISEnableInputSource(inputSource);
            NSLog(@"Enabled input source: %@", sourceID);
            CFBooleanRef isSelectable = (CFBooleanRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsSelectCapable);
            if (CFBooleanGetValue(isSelectable)) {
                TISSelectInputSource(inputSource);
                NSLog(@"Selected input source: %@", sourceID);
            }
        }
    }
    CFRelease(sourceList);
}

void deactivateInputSource() {
    CFArrayRef sourceList = TISCreateInputSourceList(NULL, true);
    for (int i = (int)CFArrayGetCount(sourceList); i > 0; --i) {
        TISInputSourceRef inputSource = (TISInputSourceRef)(CFArrayGetValueAtIndex(sourceList, i - 1));
        NSString *sourceID = (__bridge NSString *)(TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID));
        if ([sourceID isEqualToString:kSourceID]) {
            TISDisableInputSource(inputSource);
            NSLog(@"Disabled input source: %@", sourceID);
        }
    }
    CFRelease(sourceList);
}

void initPreference() {
    preference = [NSUserDefaults standardUserDefaults];
    NSDictionary *defaultPrefs = @{
        @"commitWordWithSpace" : @YES,
        @"showTranslation" : @YES,
        @"enableNextWordPrediction" : @YES,
        @"modelTier" : @(LLMModelTierMedium)
    };
    [preference registerDefaults:defaultPrefs];
}

void initNextWordPredictor() {
    BOOL enabled = [preference boolForKey:@"enableNextWordPrediction"];
    if (!enabled) {
        NSLog(@"[Typeflow] Next-word prediction is disabled");
        return;
    }

    LLMModelTier tier = (LLMModelTier)[preference integerForKey:@"modelTier"];

#if HALLELUJAH_USE_LLAMA
    // Auto-select the best available model if the preferred tier is not available
    if (![NextWordPredictor isModelAvailableForTier:tier]) {
        // Try larger models first (better quality), then smaller
        LLMModelTier fallbacks[] = { LLMModelTierXLarge, LLMModelTierLarge, LLMModelTierMedium, LLMModelTierSmall };
        BOOL found = NO;
        for (int i = 0; i < 4; i++) {
            if ([NextWordPredictor isModelAvailableForTier:fallbacks[i]]) {
                tier = fallbacks[i];
                [preference setInteger:tier forKey:@"modelTier"];
                NSLog(@"[Typeflow] Preferred model not found, auto-selected tier %ld", (long)tier);
                found = YES;
                break;
            }
        }
        if (!found) {
            NSLog(@"[Typeflow] No LLM models found. Falling back to mock mode until a model is downloaded from preferences.");
            [[NextWordPredictor shared] enableMockModeWithWordData:engine.wordsWithFrequencyAndTranslation];
            return;
        }
    }

    // Pass the word dictionary for LLM prediction filtering (loaded async — retry if nil)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (engine.wordsWithFrequencyAndTranslation) {
            [[NextWordPredictor shared] setWordDictionary:engine.wordsWithFrequencyAndTranslation];
        } else {
            // Retry once more after a longer delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (engine.wordsWithFrequencyAndTranslation) {
                    [[NextWordPredictor shared] setWordDictionary:engine.wordsWithFrequencyAndTranslation];
                }
            });
        }
    });

    NSLog(@"[Typeflow] Loading next-word prediction model (tier: %ld)...", (long)tier);
    [[NextWordPredictor shared] loadModelForTier:tier
                                      completion:^(BOOL success, NSError *error) {
                                          if (success) {
                                              NSLog(@"[Typeflow] Next-word prediction model loaded successfully (tier: %ld)", (long)tier);
                                          } else {
                                              NSLog(@"[Typeflow] Failed to load prediction model: %@. Falling back to mock mode.", error.localizedDescription);
                                              [[NextWordPredictor shared] enableMockModeWithWordData:engine.wordsWithFrequencyAndTranslation];
                                          }
                                      }];
#else
    // llama.cpp not compiled in — use mock mode with built-in bigrams
    NSLog(@"[Typeflow] Using mock prediction mode (llama.cpp not linked)");
    // Pass empty dict; mock mode uses built-in bigram/trigram tables, not word frequency data.
    // engine.wordsWithFrequencyAndTranslation is loaded async and may still be nil here.
    [[NextWordPredictor shared] enableMockModeWithWordData:@{}];
#endif
}

int main(int argc, char *argv[]) {
    if (argc > 1 && !strcmp("--install", argv[1])) {
        registerInputSource();
        deactivateInputSource();
        activateInputSource();
        return 0;
    }

    NSString *identifier = [NSBundle mainBundle].bundleIdentifier;
    IMKServer *server = [[IMKServer alloc] initWithName:(NSString *)kConnectionName bundleIdentifier:identifier];

    sharedCandidates = [[IMKCandidates alloc] initWithServer:server panelType:kIMKSingleColumnScrollingCandidatePanel];

    if (!sharedCandidates) {
        NSLog(@"Fatal error: Cannot initialize shared candidate panel with connection %@.", kConnectionName);
        return -1;
    }

    engine = [ConversionEngine sharedEngine];

    [[NSBundle mainBundle] loadNibNamed:@"AnnotationWindow" owner:[NSApplication sharedApplication] topLevelObjects:nil];

    [[NSBundle mainBundle] loadNibNamed:@"PreferencesMenu" owner:[NSApplication sharedApplication] topLevelObjects:nil];

    initPreference();

    // Initialize next-word predictor (async model loading)
    initNextWordPredictor();

    [[WebServer sharedServer] start];

    [[NSApplication sharedApplication] run];
    return 0;
}
