#import "ConversionEngine.h"
#import "NextWordPredictor.h"

NSDictionary *deserializeJSON(NSString *path) {
    NSInputStream *inputStream = [[NSInputStream alloc] initWithFileAtPath:path];
    [inputStream open];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithStream:inputStream options:0 error:nil];

    [inputStream close];
    return dict;
}

marisa::Trie trie;

@implementation ConversionEngine

+ (instancetype)sharedEngine {
    static dispatch_once_t once;
    static id sharedInstance;

    dispatch_once(&once, ^{
        sharedInstance = [self new];
        [sharedInstance loadPreparedData];
    });
    return sharedInstance;
}

- (void)loadPreparedData {
    // Dispatch the loading process to a background queue.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self loadTrie];
        self.wordsWithFrequencyAndTranslation = [self getWordsWithFrequencyAndTranslation];
        self.substitutions = [self getUserDefinedSubstitutions];
        self.pinyinDict = [self getPinyinData];
        self.phonexEncoded = [self getPhonexEncodedWords];
        self.phonexEncoder = [self getPhonexEncoder];
    });
}


- (void)loadTrie {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"google_227800_words" ofType:@"bin"];
    const char *path2 = [path cStringUsingEncoding:[NSString defaultCStringEncoding]];
    trie.load(path2);
}

- (NSDictionary *)getWordsWithFrequencyAndTranslation {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"words_with_frequency_and_translation_and_ipa" ofType:@"json"];
    return deserializeJSON(path);
}

- (NSDictionary *)getPinyinData {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"cedict" ofType:@"json"];
    return deserializeJSON(path);
}

- (NSDictionary *)getPhonexEncodedWords {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"phonex_encoded_words" ofType:@"json"];
    return deserializeJSON(path);
}

- (NSDictionary *)getUserDefinedSubstitutions {
    NSString *path = [NSString stringWithFormat:@"%@%@", NSHomeDirectory(), @"/.you_expand_me.json"];
    return deserializeJSON(path);
}

- (JSValue *)getPhonexEncoder {
    NSString *scriptPath = [[NSBundle mainBundle] pathForResource:@"phonex" ofType:@"js"];
    NSString *scriptString = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:nil];

    JSContext *context = [[JSContext alloc] init];
    [context evaluateScript:scriptString];
    return context[@"phonex"];
}

- (NSMutableArray *)wordsStartsWith:(NSString *)buffer {
    marisa::Agent agent;
    const char *query = [buffer cStringUsingEncoding:[NSString defaultCStringEncoding]];
    agent.set_query(query);

    NSMutableArray *filtered = [[NSMutableArray alloc] init];
    while (trie.predictive_search(agent)) {
        const marisa::Key key = agent.key();
        NSString *word = [[NSString alloc] initWithBytes:key.ptr() length:key.length() encoding:NSASCIIStringEncoding];
        [filtered addObject:word];
    }
    return filtered;
}

- (NSArray *)sortWordsByFrequency:(NSArray *)filtered {
    NSDictionary *words = self.wordsWithFrequencyAndTranslation;
    NSArray *sorted = [filtered sortedArrayUsingComparator:^NSComparisonResult(id word1, id word2) {
        NSDictionary *dict1 = words[word1];
        NSDictionary *dict2 = words[word2];
        int64_t n = [dict1[@"frequency"] longLongValue] - [dict2[@"frequency"] longLongValue];
        if (n > 0) {
            return (NSComparisonResult)NSOrderedAscending;
        }
        if (n < 0) {
            return (NSComparisonResult)NSOrderedDescending;
        }
        return (NSComparisonResult)NSOrderedSame;
    }];

    return sorted;
}

- (NSString *)phonexEncode:(NSString *)word {
    return [[self.phonexEncoder callWithArguments:@[ word ]] toString];
}

- (NSArray *)getTranslations:(NSString *)word {
    return (self.wordsWithFrequencyAndTranslation)[word][@"translation"];
}

- (NSString *)getPhoneticSymbolOfWord:(NSString *)candidateString {
    if (candidateString && candidateString.length > 3) {
        NSString *word = candidateString.lowercaseString;
        return (self.wordsWithFrequencyAndTranslation)[word][@"ipa"];
    }
    return nil;
}

- (NSString *)getAnnotation:(NSString *)word {
    NSString *input = word.lowercaseString;
    NSArray *translation = [self getTranslations:input];
    if (translation && translation.count > 0) {
        NSString *translationText;
        NSString *phoneticSymbol = [self getPhoneticSymbolOfWord:input];
        if (phoneticSymbol.length > 0) {
            NSArray *list = @[ [NSString stringWithFormat:@"[%@]", phoneticSymbol] ];
            translationText = [[list arrayByAddingObjectsFromArray:translation] componentsJoinedByString:@"\n"];
        } else {
            translationText = [translation componentsJoinedByString:@"\n"];
        }
        return translationText;
    } else {
        return @"";
    }
}

- (NSArray *)sortByDamerauLevenshteinDistance:(NSArray *)original inputText:(NSString *)text {
    NSMutableArray *mutableArray = [NSMutableArray new];
    for (NSString *word in original) {
        NSUInteger distance = [text mdc_levenshteinDistanceTo:word];
        if (distance <= 3) { // Max edit distance: 3
            [mutableArray addObject:@{@"w" : word, @"d" : @(distance)}];
        }
    }
    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"d" ascending:YES];
    NSArray *sorted = [mutableArray sortedArrayUsingDescriptors:@[ descriptor ]];
    NSMutableArray *result = [NSMutableArray new];
    for (NSDictionary *obj in sorted) {
        [result addObject:obj[@"w"]];
    }
    return [result copy];
}

- (NSArray *)getSuggestionOfSpellChecker:(NSString *)buffer {
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSRange range = NSMakeRange(0, buffer.length);
    NSArray *result = [checker guessesForWordRange:range inString:buffer language:@"en" inSpellDocumentWithTag:0];

    if (buffer.length > 3) {
        NSArray *words = (self.phonexEncoded)[[self phonexEncode:buffer]];
        NSArray *wordsWithSimilarPhone = [self sortByDamerauLevenshteinDistance:words inputText:buffer];
        if (wordsWithSimilarPhone && wordsWithSimilarPhone.count > 0) {
            NSUInteger range = 4; // 0~5
            NSMutableArray *finalResult = [NSMutableArray arrayWithArray:[self subarrayWithRang:result range:range]];
            [finalResult addObjectsFromArray:[self subarrayWithRang:wordsWithSimilarPhone range:range]];
            return finalResult;
        }
    }
    return result;
}

- (NSArray *)subarrayWithRang:(NSArray *)array range:(NSUInteger)range {
    NSUInteger count = array.count;
    NSUInteger limit = count >= range ? range : count;
    return [array subarrayWithRange:NSMakeRange(0, limit)];
}

// Common English contractions for candidate injection
static NSArray<NSString *> *_commonContractions;

+ (NSArray<NSString *> *)commonContractions {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _commonContractions = @[
            @"don't", @"doesn't", @"didn't", @"isn't", @"aren't", @"wasn't", @"weren't",
            @"won't", @"wouldn't", @"couldn't", @"shouldn't", @"can't", @"haven't", @"hasn't",
            @"hadn't", @"mustn't", @"needn't", @"that's", @"there's", @"here's", @"what's",
            @"who's", @"where's", @"when's", @"how's", @"it's", @"he's", @"she's", @"let's",
            @"i'm", @"i've", @"i'd", @"i'll", @"you're", @"you've", @"you'd", @"you'll",
            @"we're", @"we've", @"we'd", @"we'll", @"they're", @"they've", @"they'd", @"they'll",
            @"he'd", @"he'll", @"she'd", @"she'll", @"it'd", @"it'll",
            @"ain't", @"o'clock", @"ma'am", @"'cause", @"'til"
        ];
    });
    return _commonContractions;
}

- (NSArray *)getCandidates:(NSString *)originalInput {
    NSString *buffer = originalInput.lowercaseString;
    NSMutableArray *result = [[NSMutableArray alloc] init];

    if (buffer && buffer.length > 0) {
        if (self.substitutions && self.substitutions[buffer]) {
            [result addObject:self.substitutions[buffer]];
        }

        NSMutableArray *filtered = [self wordsStartsWith:buffer];
        if (filtered && filtered.count > 0) {
            NSArray *sorted = [self sortWordsByFrequency:filtered];
            [result addObjectsFromArray:sorted];
        }

        // Always run spell checker to catch typos (e.g., "adn" → "and").
        // Insert corrections near the top so they're visible even when
        // the trie found matches (which may be obscure words like "adnexal").
        if (buffer.length >= 2) {
            NSArray *spellSuggestions = [self getSuggestionOfSpellChecker:buffer];
            if (spellSuggestions && spellSuggestions.count > 0) {
                // Insert after raw input (position 0) but before trie results
                NSUInteger insertIdx = (filtered && filtered.count > 0) ? 0 : 0;
                for (NSString *suggestion in spellSuggestions) {
                    if (![result containsObject:suggestion] && ![suggestion isEqualToString:buffer]) {
                        [result insertObject:suggestion atIndex:insertIdx];
                        insertIdx++;
                        if (insertIdx >= 3) break; // At most 3 spell corrections
                    }
                }
            }
        }

        // Inject matching contractions (e.g., "hav" → "haven't")
        for (NSString *contraction in [ConversionEngine commonContractions]) {
            if ([contraction hasPrefix:buffer] && ![result containsObject:contraction]) {
                // Insert after the first few dictionary matches for visibility
                NSUInteger insertIdx = MIN(3, result.count);
                [result insertObject:contraction atIndex:insertIdx];
            }
        }

        if (self.pinyinDict && self.pinyinDict[buffer]) {
            [result addObjectsFromArray:self.pinyinDict[buffer]];
        }

        if (result.count > 50) {
            result = [NSMutableArray arrayWithArray:[result subarrayWithRange:NSMakeRange(0, 49)]];
        }
        [result removeObject:buffer];
        [result insertObject:buffer atIndex:0];
    }

    NSMutableArray *result2 = [[NSMutableArray alloc] init];
    for (NSString *word in result) {
        // case sensitive input
        if ([word hasPrefix:buffer]) {
            [result2 addObject:[NSString stringWithFormat:@"%@%@", originalInput, [word substringFromIndex:originalInput.length]]];
        } else {
            [result2 addObject:word];
        }
    }
    NSOrderedSet *orderedSet = [NSOrderedSet orderedSetWithArray:result2];
    NSArray *arrayWithoutDuplicates = orderedSet.array;
    return [NSArray arrayWithArray:arrayWithoutDuplicates];
}

- (NSArray *)getCandidates:(NSString *)originalInput withContext:(NSString *)context {
    NSArray *baseCandidates = [self getCandidates:originalInput];

    if (!context || context.length == 0 || !originalInput || originalInput.length == 0) {
        return baseCandidates;
    }

    // Get contextual scores from the LLM (uses cached logits, no new inference)
    NSDictionary<NSString *, NSNumber *> *contextScores =
        [[NextWordPredictor shared] contextualScoresForPrefix:originalInput.lowercaseString
                                                     context:context];

    if (!contextScores || contextScores.count == 0) {
        NSLog(@"[ConversionEngine] No contextual scores available; using frequency order");
        return baseCandidates;
    }
    NSLog(@"[ConversionEngine] Reranking candidates with %lu contextual scores", (unsigned long)contextScores.count);

    // Keep raw input as first candidate (position 0), rerank the rest
    NSMutableArray *boosted = [NSMutableArray array];
    NSMutableArray *rest = [NSMutableArray array];

    BOOL firstIsRawInput = baseCandidates.count > 0 &&
        [baseCandidates[0] isEqualToString:originalInput];
    NSInteger startIdx = firstIsRawInput ? 1 : 0;

    for (NSInteger i = startIdx; i < (NSInteger)baseCandidates.count; i++) {
        NSString *candidate = baseCandidates[i];
        NSString *lowerCandidate = candidate.lowercaseString;
        NSNumber *score = contextScores[lowerCandidate];
        if (score) {
            [boosted addObject:@{@"word": candidate, @"score": score}];
        } else {
            [rest addObject:candidate];
        }
    }

    // Sort boosted candidates by LLM score (descending)
    [boosted sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"score"] compare:a[@"score"]];
    }];

    // Reassemble: raw input first, then boosted, then rest
    NSMutableArray *reranked = [NSMutableArray array];
    if (firstIsRawInput) {
        [reranked addObject:baseCandidates[0]];
    }
    for (NSDictionary *item in boosted) {
        [reranked addObject:item[@"word"]];
    }
    [reranked addObjectsFromArray:rest];

    return [reranked copy];
}

@end
