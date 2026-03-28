#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, LLMModelTier) {
    LLMModelTierSmall = 0,   // ~135M params, fastest, ~138MB
    LLMModelTierMedium = 1,  // ~0.5B params, balanced, ~506MB
    LLMModelTierLarge = 2,   // ~1.5B params, accurate, ~940MB
    LLMModelTierXLarge = 3   // ~3B params (Qwen2.5-3B), best quality, ~2.1GB
};

typedef void (^PredictionCompletionBlock)(NSArray<NSString *> *_Nullable predictions);

@interface NextWordPredictor : NSObject

@property(nonatomic, readonly) BOOL isModelLoaded;
@property(nonatomic, readonly) LLMModelTier currentTier;
@property(nonatomic, readonly) BOOL isMockMode;
@property(nonatomic, readonly) BOOL isDownloadingModel;
@property(nonatomic, readonly) double downloadProgress;
@property(nonatomic, readonly) LLMModelTier downloadingTier;
@property(nonatomic, readonly, copy, nullable) NSString *downloadStatus;

+ (instancetype)shared;

/// Load model for the specified tier. Runs async on background queue.
- (void)loadModelForTier:(LLMModelTier)tier completion:(void (^_Nullable)(BOOL success, NSError *_Nullable error))completion;

/// Enable mock mode for testing (uses word frequency data instead of LLM).
/// Pass the wordsWithFrequencyAndTranslation dictionary from ConversionEngine.
- (void)enableMockModeWithWordData:(NSDictionary *)wordData;

/// Set the word dictionary for filtering LLM predictions (keys = valid English words).
- (void)setWordDictionary:(NSDictionary *)wordData;

/// Unload the current model and free memory.
- (void)unloadModel;

/// Predict next words given a context string (recent words).
/// Returns up to `count` predictions via the completion block on the main queue.
- (void)predictNextWords:(NSString *)context
                   count:(NSInteger)count
              completion:(PredictionCompletionBlock)completion;

/// Cancel any in-flight prediction request.
- (void)cancelPendingPrediction;

/// Get contextual scores for candidate words matching a prefix.
/// Uses cached LLM logits from the most recent context to rank word completions.
/// Returns a dictionary mapping lowercase words to NSNumber scores (higher = more relevant).
/// Called synchronously — uses cached data, no new LLM inference.
- (NSDictionary<NSString *, NSNumber *> *)contextualScoresForPrefix:(NSString *)prefix
                                                            context:(NSString *)context;

/// Get the model directory path (~/Library/Application Support/Typeflow/models/)
+ (NSString *)modelDirectoryPath;

/// Get the expected model filename for a given tier.
+ (NSString *)modelFilenameForTier:(LLMModelTier)tier;

/// Check if the model file exists for a given tier.
+ (BOOL)isModelAvailableForTier:(LLMModelTier)tier;

/// Download the specified model tier into the app support models directory.
/// Returns NO immediately if a download cannot be started.
- (BOOL)downloadModelForTier:(LLMModelTier)tier
                       error:(NSError *_Nullable *_Nullable)error
                  completion:(void (^_Nullable)(BOOL success, NSError *_Nullable error))completion;

@end
