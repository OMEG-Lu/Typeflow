#import "WebServer.h"
#import "GCDWebServer.h"
#import "GCDWebServerDataRequest.h"
#import "GCDWebServerDataResponse.h"
#import "NextWordPredictor.h"

extern NSUserDefaults *preference;

NSString *TRANSLATION_KEY = @"showTranslation";
NSString *COMMIT_WORD_WITH_SPACE_KEY = @"commitWordWithSpace";
NSString *ENABLE_PREDICTION_KEY = @"enableNextWordPrediction";
NSString *MODEL_TIER_KEY = @"modelTier";
NSString *DOWNLOAD_TIER_KEY = @"tier";


@interface WebServer ()

@property(nonatomic, strong) GCDWebServer *server;

@end

@implementation WebServer

static int port = 62720;

static NSDictionary *ModelStatusPayload(void) {
    NextWordPredictor *predictor = [NextWordPredictor shared];
    return @{
        @"isModelLoaded" : @(predictor.isModelLoaded),
        @"currentTier" : @(predictor.currentTier),
        @"smallModelAvailable" : @([NextWordPredictor isModelAvailableForTier:LLMModelTierSmall]),
        @"mediumModelAvailable" : @([NextWordPredictor isModelAvailableForTier:LLMModelTierMedium]),
        @"largeModelAvailable" : @([NextWordPredictor isModelAvailableForTier:LLMModelTierLarge]),
        @"xlargeModelAvailable" : @([NextWordPredictor isModelAvailableForTier:LLMModelTierXLarge]),
        @"isDownloading" : @(predictor.isDownloadingModel),
        @"downloadProgress" : @(predictor.downloadProgress),
        @"downloadingTier" : @(predictor.downloadingTier),
        @"downloadStatus" : predictor.downloadStatus ?: @"",
        @"modelDirectory" : [NextWordPredictor modelDirectoryPath]
    };
}

+ (instancetype)sharedServer {
    static WebServer *server = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        server = [[WebServer alloc] init];
    });
    return server;
}

- (void)start {
    if (self.server) {
        return;
    }

    GCDWebServer *webServer = [[GCDWebServer alloc] init];
    [webServer addGETHandlerForBasePath:@"/"
                          directoryPath:[NSString stringWithFormat:@"%@/%@", [NSBundle mainBundle].resourcePath, @"web"]
                          indexFilename:nil
                               cacheAge:3600
                     allowRangeRequests:YES];

    [webServer addHandlerForMethod:@"GET"
                              path:@"/preference"
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          return [GCDWebServerDataResponse responseWithJSONObject:
                                  @{
                                    TRANSLATION_KEY : @([preference boolForKey:TRANSLATION_KEY]),
                                    COMMIT_WORD_WITH_SPACE_KEY : @([preference boolForKey:COMMIT_WORD_WITH_SPACE_KEY]),
                                    ENABLE_PREDICTION_KEY : @([preference boolForKey:ENABLE_PREDICTION_KEY]),
                                    MODEL_TIER_KEY : @([preference integerForKey:MODEL_TIER_KEY])
                                   }
                                 ];
                      }];

    [webServer addHandlerForMethod:@"POST"
                              path:@"/preference"
                      requestClass:[GCDWebServerDataRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          NSDictionary *data = ((GCDWebServerDataRequest *)request).jsonObject;
                          BOOL previousEnablePrediction = [preference boolForKey:ENABLE_PREDICTION_KEY];
                          NSInteger previousTier = [preference integerForKey:MODEL_TIER_KEY];

                          bool showTranslation = [data[TRANSLATION_KEY] boolValue];
                          [preference setBool:showTranslation forKey:TRANSLATION_KEY];

                          bool commitWordWithSpace = [data[COMMIT_WORD_WITH_SPACE_KEY] boolValue];
                          [preference setBool:commitWordWithSpace forKey:COMMIT_WORD_WITH_SPACE_KEY];

                          // Handle prediction preferences
                          BOOL enablePrediction = previousEnablePrediction;
                          if (data[ENABLE_PREDICTION_KEY] != nil) {
                              enablePrediction = [data[ENABLE_PREDICTION_KEY] boolValue];
                              [preference setBool:enablePrediction forKey:ENABLE_PREDICTION_KEY];

                              if (!enablePrediction) {
                                  // Unload model to free memory when prediction is disabled
                                  [[NextWordPredictor shared] unloadModel];
                              }
                          }

                          NSInteger selectedTier = previousTier;
                          if (data[MODEL_TIER_KEY] != nil) {
                              selectedTier = [data[MODEL_TIER_KEY] integerValue];
                              [preference setInteger:selectedTier forKey:MODEL_TIER_KEY];
                          }

                          if (enablePrediction && (!previousEnablePrediction || selectedTier != previousTier)) {
                              LLMModelTier tier = (LLMModelTier)selectedTier;
                              if ([NextWordPredictor isModelAvailableForTier:tier]) {
                                  [[NextWordPredictor shared] loadModelForTier:tier completion:^(BOOL success, NSError *error) {
                                      if (success) {
                                          NSLog(@"[Typeflow] Model reloaded for tier: %ld", (long)selectedTier);
                                      } else {
                                          NSLog(@"[Typeflow] Failed to reload model: %@", error.localizedDescription);
                                      }
                                  }];
                              }
                          }

                          return [GCDWebServerDataResponse responseWithJSONObject:data];
                      }];

    // Model status endpoint
    [webServer addHandlerForMethod:@"GET"
                              path:@"/model-status"
                      requestClass:[GCDWebServerRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          return [GCDWebServerDataResponse responseWithJSONObject:ModelStatusPayload()];
                      }];

    [webServer addHandlerForMethod:@"POST"
                              path:@"/download-model"
                      requestClass:[GCDWebServerDataRequest class]
                      processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                          NSDictionary *data = ((GCDWebServerDataRequest *)request).jsonObject;
                          NSInteger tierValue = [data[DOWNLOAD_TIER_KEY] integerValue];

                          if (tierValue < LLMModelTierSmall || tierValue > LLMModelTierXLarge) {
                              return [GCDWebServerDataResponse responseWithJSONObject:@{
                                  @"started" : @NO,
                                  @"error" : @"Invalid model tier."
                              }];
                          }

                          LLMModelTier tier = (LLMModelTier)tierValue;
                          NSError *downloadError = nil;
                          BOOL started = [[NextWordPredictor shared] downloadModelForTier:tier
                                                                                     error:&downloadError
                                                                                completion:^(BOOL success, NSError *error) {
                                                                                    if (!success) {
                                                                                        NSLog(@"[Typeflow] Model download failed: %@", error.localizedDescription);
                                                                                        return;
                                                                                    }

                                                                                    if ([preference boolForKey:ENABLE_PREDICTION_KEY] &&
                                                                                        [preference integerForKey:MODEL_TIER_KEY] == tierValue) {
                                                                                        [[NextWordPredictor shared] loadModelForTier:tier completion:^(BOOL loadSuccess, NSError *loadError) {
                                                                                            if (!loadSuccess) {
                                                                                                NSLog(@"[Typeflow] Downloaded model failed to load: %@", loadError.localizedDescription);
                                                                                            }
                                                                                        }];
                                                                                    }
                                                                                }];

                          NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:ModelStatusPayload()];
                          response[@"started"] = @(started);
                          if (downloadError) {
                              response[@"error"] = downloadError.localizedDescription;
                          }
                          return [GCDWebServerDataResponse responseWithJSONObject:response];
                      }];

    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[GCDWebServerOption_Port] = @(port);
    options[GCDWebServerOption_BindToLocalhost] = @YES;

    [webServer startWithOptions:options error:nil];
    self.server = webServer;
}

@end
