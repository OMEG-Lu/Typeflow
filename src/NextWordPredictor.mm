#import "NextWordPredictor.h"
#include <algorithm>
#include <string>
#include <vector>

// ==============================================================================
// Conditional compilation:
//   - Define HALLELUJAH_USE_LLAMA=1 to use real llama.cpp LLM inference
//   - Without it (default), mock mode is available for testing without llama.cpp
// ==============================================================================
#if HALLELUJAH_USE_LLAMA
#include "llama.h"
#endif

static NSString *const kModelDirName = @"models";
static NSString *const kAppSupportDir = @"Typeflow";

// Model filenames for each tier (GGUF format)
static NSString *const kModelFileSmall = @"smollm-135m-q8_0.gguf";
static NSString *const kModelFileMedium = @"qwen2-0.5b-q8_0.gguf";
static NSString *const kModelFileLarge = @"qwen2-1.5b-q4_k_m.gguf";
static NSString *const kModelFileXLarge = @"qwen2.5-3b-q4_k_m.gguf";

// Model download URLs (Hugging Face)
static NSString *const kModelURLSmall = @"https://huggingface.co/QuantFactory/SmolLM-135M-GGUF/resolve/main/SmolLM-135M.Q8_0.gguf";
static NSString *const kModelURLMedium = @"https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q8_0.gguf";
static NSString *const kModelURLLarge = @"https://huggingface.co/Qwen/Qwen2-1.5B-Instruct-GGUF/resolve/main/qwen2-1_5b-instruct-q4_k_m.gguf";
static NSString *const kModelURLXLarge = @"https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf";

// Context sizes per tier (in tokens)
static const int kContextSizeSmall = 256;
static const int kContextSizeMedium = 512;
static const int kContextSizeLarge = 512;
static const int kContextSizeXLarge = 1024;

// ---- Common English words filter for LLM predictions ----
static NSSet<NSString *> *_commonEnglishWords;

static void initCommonEnglishWords() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // ~2000 most common English words — used to filter LLM output
        NSArray *words = @[
            // Function words
            @"the", @"be", @"to", @"of", @"and", @"a", @"in", @"that", @"have", @"i",
            @"it", @"for", @"not", @"on", @"with", @"he", @"as", @"you", @"do", @"at",
            @"this", @"but", @"his", @"by", @"from", @"they", @"we", @"say", @"her", @"she",
            @"or", @"an", @"will", @"my", @"one", @"all", @"would", @"there", @"their", @"what",
            @"so", @"up", @"out", @"if", @"about", @"who", @"get", @"which", @"go", @"me",
            @"when", @"make", @"can", @"like", @"time", @"no", @"just", @"him", @"know", @"take",
            @"people", @"into", @"year", @"your", @"good", @"some", @"could", @"them", @"see", @"other",
            @"than", @"then", @"now", @"look", @"only", @"come", @"its", @"over", @"think", @"also",
            @"back", @"after", @"use", @"two", @"how", @"our", @"work", @"first", @"well", @"way",
            @"even", @"new", @"want", @"because", @"any", @"these", @"give", @"day", @"most", @"us",
            // Common content words
            @"find", @"here", @"thing", @"many", @"still", @"own", @"need", @"should", @"tell",
            @"try", @"leave", @"call", @"keep", @"let", @"begin", @"seem", @"help", @"show",
            @"hear", @"play", @"run", @"move", @"live", @"believe", @"hold", @"bring", @"happen",
            @"write", @"provide", @"sit", @"stand", @"lose", @"pay", @"meet", @"include", @"continue",
            @"set", @"learn", @"change", @"lead", @"understand", @"watch", @"follow", @"stop", @"create",
            @"speak", @"read", @"allow", @"add", @"spend", @"grow", @"open", @"walk", @"win", @"offer",
            @"remember", @"love", @"consider", @"appear", @"buy", @"wait", @"serve", @"die", @"send", @"expect",
            @"build", @"stay", @"fall", @"cut", @"reach", @"kill", @"remain", @"suggest", @"raise", @"pass",
            @"sell", @"require", @"report", @"decide", @"pull", @"develop", @"feel", @"start", @"turn", @"ask",
            @"put", @"become", @"might", @"must", @"may", @"such", @"very", @"much", @"before", @"too",
            @"really", @"already", @"through", @"right", @"never", @"long", @"always", @"another", @"around",
            @"however", @"every", @"between", @"both", @"few", @"those", @"under", @"while", @"again",
            @"last", @"during", @"away", @"each", @"great", @"little", @"man", @"same", @"big", @"group",
            @"woman", @"place", @"important", @"world", @"hand", @"high", @"old", @"part", @"small",
            @"number", @"home", @"life", @"since", @"where", @"down", @"side", @"head", @"end", @"point",
            @"large", @"name", @"next", @"case", @"state", @"school", @"problem", @"system", @"program",
            @"question", @"possible", @"company", @"story", @"area", @"power", @"different", @"sure",
            @"water", @"family", @"fact", @"enough", @"country", @"study", @"night", @"room", @"house",
            @"morning", @"kind", @"young", @"line", @"political", @"without", @"being", @"off", @"once",
            @"form", @"money", @"together", @"until", @"able", @"against", @"among", @"often", @"free",
            @"real", @"nothing", @"less", @"something", @"war", @"far", @"actually", @"best",
            @"going", @"looking", @"working", @"trying", @"doing", @"using", @"having", @"getting",
            @"making", @"coming", @"taking", @"giving", @"saying", @"thinking", @"feeling",
            // Tech/modern words
            @"computer", @"phone", @"email", @"data", @"online", @"website", @"app", @"software",
            @"file", @"code", @"project", @"team", @"meeting", @"message", @"today", @"tomorrow",
            @"yesterday", @"week", @"month", @"idea", @"issue", @"update", @"check", @"review",
            @"test", @"please", @"thanks", @"sorry", @"sure", @"right", @"okay", @"yes",
            @"available", @"information", @"business", @"social", @"process", @"experience",
            @"service", @"result", @"market", @"support", @"report", @"level", @"plan",
            @"research", @"second", @"third", @"several", @"national", @"order", @"development",
            @"health", @"local", @"game", @"early", @"member", @"above", @"half", @"though",
            @"almost", @"interest", @"quite", @"already", @"whether", @"hard", @"probably",
            @"perhaps", @"certainly", @"especially", @"usually", @"quickly", @"recently",
            // More common words
            @"city", @"book", @"food", @"model", @"job", @"friend", @"type", @"ago", @"child",
            @"person", @"student", @"word", @"body", @"car", @"door", @"table", @"music", @"face",
            @"eye", @"road", @"heart", @"mind", @"class", @"court", @"inside", @"close", @"across",
            @"behind", @"toward", @"later", @"along", @"themselves", @"itself", @"myself", @"yourself",
            @"himself", @"herself", @"everyone", @"everything", @"anyone", @"anything", @"someone",
            @"sometimes", @"maybe", @"whole", @"rather", @"might", @"although", @"bit",
            @"done", @"gone", @"seen", @"known", @"given", @"taken", @"made", @"found", @"left",
            @"told", @"asked", @"needed", @"wanted", @"used", @"called", @"tried", @"started",
            @"based", @"able", @"clear", @"full", @"true", @"wrong", @"strong", @"late",
            @"better", @"possible", @"easy", @"simple", @"black", @"white", @"short",
            @"human", @"public", @"others", @"least", @"common", @"special", @"past",
            @"future", @"present", @"recent", @"reason", @"action", @"yet", @"either",
            @"within", @"cost", @"near", @"particular", @"total", @"general",
            @"happy", @"bad", @"nice", @"beautiful", @"fine", @"cool", @"amazing", @"wonderful",
            @"pretty", @"perfect", @"ready", @"sorry", @"afraid", @"careful", @"interesting",
            @"important", @"necessary", @"normal", @"natural", @"similar", @"final", @"major",
            @"current", @"complete", @"entire", @"original", @"single", @"successful",
            // Verbs (more)
            @"accept", @"achieve", @"announce", @"apply", @"argue", @"arrive", @"assume",
            @"avoid", @"break", @"carry", @"catch", @"cause", @"choose", @"claim", @"close",
            @"compare", @"concern", @"contain", @"cover", @"deal", @"deliver", @"demand",
            @"describe", @"design", @"determine", @"discuss", @"discover", @"draw", @"drive",
            @"drop", @"eat", @"enjoy", @"enter", @"establish", @"examine", @"exist", @"explain",
            @"express", @"face", @"fill", @"finish", @"fly", @"force", @"forget", @"handle",
            @"hang", @"hit", @"hope", @"identify", @"imagine", @"improve", @"increase",
            @"indicate", @"involve", @"join", @"jump", @"lack", @"launch", @"lay", @"lie",
            @"listen", @"manage", @"mark", @"matter", @"mean", @"measure", @"mention",
            @"miss", @"note", @"notice", @"occur", @"operate", @"perform", @"pick", @"place",
            @"point", @"prepare", @"present", @"prevent", @"produce", @"protect", @"prove",
            @"push", @"realize", @"receive", @"recognize", @"record", @"reduce", @"reflect",
            @"refuse", @"relate", @"release", @"remove", @"replace", @"represent", @"respond",
            @"rest", @"result", @"return", @"reveal", @"rise", @"save", @"seek", @"share",
            @"shoot", @"sign", @"sit", @"sleep", @"smile", @"sort", @"sound", @"spread",
            @"step", @"strike", @"suffer", @"support", @"suppose", @"talk", @"teach",
            @"tend", @"thank", @"throw", @"touch", @"train", @"travel", @"treat", @"visit",
            @"voice", @"vote", @"wear", @"wish", @"wonder", @"worry",
            // Adjectives/adverbs
            @"likely", @"certain", @"significant", @"various", @"serious", @"popular",
            @"traditional", @"professional", @"effective", @"official", @"potential",
            @"personal", @"physical", @"digital", @"medical", @"additional",
            @"immediately", @"eventually", @"finally", @"suddenly", @"extremely",
            @"obviously", @"apparently", @"completely", @"absolutely", @"definitely",
            @"basically", @"seriously", @"exactly", @"directly", @"simply",
            // Noplace
            @"million", @"thousand", @"hundred", @"billion", @"percent",
            @"article", @"material", @"product", @"technology", @"security", @"policy",
            @"situation", @"position", @"period", @"practice", @"effort", @"environment",
            @"activity", @"performance", @"attention", @"education", @"building",
            @"community", @"industry", @"management", @"condition", @"decision",
            @"moment", @"history", @"language", @"network", @"office", @"paper",
            @"picture", @"season", @"society", @"century", @"design", @"energy",
            @"response", @"standard", @"resource", @"quality", @"value", @"image",
            @"access", @"account", @"source", @"effect", @"event", @"structure",
            @"culture", @"example", @"option", @"feature", @"chance", @"rule",
            @"thought", @"couple", @"answer", @"price", @"theory", @"department",
        ];
        _commonEnglishWords = [NSSet setWithArray:words];
    });
}

// ---- Bigram + trigram tables for mock mode ----
static NSDictionary<NSString *, NSArray<NSString *> *> *_mockBigrams;
static NSDictionary<NSString *, NSArray<NSString *> *> *_mockTrigrams;

static void initMockBigrams() {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _mockBigrams = @{
            // Pronouns
            @"i" : @[ @"am", @"have", @"think", @"want", @"will", @"can", @"was", @"need", @"know", @"like", @"don't", @"would", @"could", @"should", @"just" ],
            @"you" : @[ @"are", @"can", @"have", @"will", @"should", @"need", @"want", @"know", @"might", @"would", @"could", @"don't", @"may", @"must", @"just" ],
            @"he" : @[ @"is", @"was", @"has", @"will", @"would", @"can", @"said", @"had", @"could", @"should", @"didn't", @"also", @"just", @"never", @"might" ],
            @"she" : @[ @"is", @"was", @"has", @"will", @"would", @"can", @"said", @"had", @"could", @"should", @"didn't", @"also", @"just", @"never", @"might" ],
            @"it" : @[ @"is", @"was", @"will", @"would", @"can", @"has", @"could", @"should", @"seems", @"looks", @"takes", @"might", @"doesn't", @"also", @"may" ],
            @"we" : @[ @"are", @"have", @"can", @"will", @"should", @"need", @"want", @"were", @"would", @"could", @"don't", @"also", @"just", @"may", @"must" ],
            @"they" : @[ @"are", @"have", @"will", @"can", @"were", @"would", @"should", @"could", @"want", @"need", @"don't", @"also", @"just", @"may", @"didn't" ],
            // Articles & determiners
            @"the" : @[ @"first", @"best", @"most", @"same", @"new", @"next", @"last", @"other", @"only", @"main", @"right", @"whole", @"old", @"real", @"current" ],
            @"a" : @[ @"new", @"good", @"great", @"little", @"big", @"long", @"few", @"small", @"large", @"single", @"simple", @"better", @"different", @"certain", @"bit" ],
            @"an" : @[ @"important", @"interesting", @"example", @"issue", @"error", @"email", @"update", @"option", @"idea", @"hour", @"easy", @"app", @"open", @"old", @"extra" ],
            @"my" : @[ @"own", @"first", @"name", @"team", @"work", @"code", @"phone", @"email", @"last", @"new", @"old", @"best", @"next", @"other", @"computer" ],
            @"your" : @[ @"own", @"first", @"name", @"team", @"work", @"code", @"phone", @"email", @"last", @"new", @"other", @"help", @"best", @"next", @"message" ],
            @"his" : @[ @"own", @"first", @"name", @"team", @"work", @"phone", @"last", @"new", @"old", @"best", @"next", @"other", @"head", @"hand", @"wife" ],
            @"her" : @[ @"own", @"first", @"name", @"team", @"work", @"phone", @"last", @"new", @"old", @"best", @"next", @"other", @"head", @"hand", @"husband" ],
            @"their" : @[ @"own", @"first", @"team", @"work", @"new", @"last", @"best", @"next", @"other", @"way", @"time", @"data", @"code", @"names", @"lives" ],
            @"our" : @[ @"own", @"first", @"team", @"work", @"new", @"last", @"best", @"next", @"other", @"way", @"time", @"data", @"code", @"goal", @"plan" ],
            @"some" : @[ @"of", @"people", @"time", @"kind", @"way", @"things", @"more", @"other", @"cases", @"point", @"reason", @"ideas", @"new", @"issues", @"changes" ],
            @"all" : @[ @"the", @"of", @"right", @"good", @"day", @"over", @"done", @"set", @"about", @"these", @"those", @"that", @"things", @"you", @"we" ],
            // Verbs (be)
            @"is" : @[ @"not", @"the", @"a", @"very", @"also", @"just", @"that", @"still", @"being", @"now", @"it", @"there", @"this", @"already", @"really" ],
            @"are" : @[ @"not", @"the", @"you", @"we", @"they", @"there", @"also", @"very", @"still", @"being", @"some", @"many", @"all", @"going", @"looking" ],
            @"was" : @[ @"not", @"the", @"a", @"very", @"also", @"just", @"still", @"being", @"born", @"able", @"going", @"trying", @"looking", @"working", @"really" ],
            @"were" : @[ @"not", @"the", @"able", @"going", @"also", @"just", @"still", @"looking", @"trying", @"working", @"doing", @"using", @"you", @"we", @"they" ],
            @"been" : @[ @"a", @"the", @"working", @"doing", @"able", @"using", @"trying", @"looking", @"going", @"there", @"here", @"made", @"done", @"updated", @"changed" ],
            // Verbs (have)
            @"have" : @[ @"been", @"to", @"a", @"the", @"not", @"any", @"no", @"some", @"more", @"already", @"just", @"also", @"never", @"it", @"this" ],
            @"has" : @[ @"been", @"to", @"a", @"the", @"not", @"no", @"also", @"already", @"never", @"always", @"just", @"some", @"its", @"many", @"more" ],
            @"had" : @[ @"been", @"to", @"a", @"the", @"not", @"no", @"already", @"never", @"just", @"some", @"it", @"this", @"any", @"an", @"enough" ],
            // Verbs (modal)
            @"will" : @[ @"be", @"not", @"have", @"need", @"also", @"help", @"make", @"take", @"give", @"get", @"work", @"try", @"do", @"start", @"continue" ],
            @"would" : @[ @"be", @"have", @"like", @"not", @"need", @"make", @"take", @"give", @"say", @"do", @"prefer", @"suggest", @"recommend", @"appreciate", @"love" ],
            @"can" : @[ @"be", @"also", @"help", @"make", @"use", @"see", @"find", @"get", @"do", @"take", @"try", @"start", @"check", @"add", @"create" ],
            @"could" : @[ @"be", @"have", @"not", @"also", @"use", @"help", @"make", @"try", @"you", @"we", @"potentially", @"possibly", @"still", @"just", @"even" ],
            @"should" : @[ @"be", @"have", @"not", @"we", @"I", @"also", @"work", @"help", @"make", @"use", @"try", @"probably", @"just", @"still", @"consider" ],
            @"may" : @[ @"be", @"have", @"not", @"also", @"need", @"want", @"take", @"cause", @"help", @"require", @"include", @"vary", @"result", @"lead", @"affect" ],
            @"might" : @[ @"be", @"have", @"not", @"also", @"need", @"want", @"help", @"cause", @"work", @"take", @"look", @"seem", @"consider", @"try", @"even" ],
            @"must" : @[ @"be", @"have", @"not", @"also", @"first", @"include", @"ensure", @"provide", @"follow", @"meet", @"make", @"do", @"get", @"take", @"complete" ],
            // Verbs (do)
            @"do" : @[ @"not", @"you", @"it", @"the", @"this", @"that", @"we", @"they", @"so", @"anything", @"something", @"more", @"is", @"what", @"I" ],
            @"does" : @[ @"not", @"it", @"the", @"this", @"that", @"anyone", @"anyone", @"work", @"make", @"seem" ],
            @"did" : @[ @"not", @"you", @"it", @"the", @"that", @"this", @"he", @"she", @"we", @"they", @"I", @"so", @"anyone", @"everything", @"nothing" ],
            @"don't" : @[ @"know", @"think", @"want", @"have", @"need", @"worry", @"forget", @"understand", @"see", @"like", @"mind", @"care", @"remember", @"feel", @"use" ],
            @"didn't" : @[ @"know", @"think", @"want", @"have", @"get", @"see", @"work", @"expect", @"understand", @"mean", @"realize", @"find", @"like", @"make", @"need" ],
            @"doesn't" : @[ @"work", @"seem", @"matter", @"mean", @"have", @"look", @"make", @"exist", @"need", @"appear", @"support", @"require", @"change", @"help", @"affect" ],
            // Common verbs
            @"want" : @[ @"to", @"it", @"the", @"a", @"that", @"this", @"you", @"me", @"them", @"something" ],
            @"need" : @[ @"to", @"a", @"the", @"more", @"some", @"it", @"this", @"that", @"help", @"your" ],
            @"think" : @[ @"about", @"that", @"it", @"the", @"this", @"we", @"I", @"so", @"of", @"you" ],
            @"know" : @[ @"that", @"what", @"how", @"if", @"about", @"the", @"it", @"where", @"when", @"why" ],
            @"make" : @[ @"it", @"a", @"the", @"sure", @"sense", @"up", @"any", @"this", @"changes", @"progress" ],
            @"get" : @[ @"the", @"a", @"it", @"back", @"to", @"this", @"that", @"more", @"started", @"into" ],
            @"go" : @[ @"to", @"back", @"ahead", @"through", @"with", @"for", @"out", @"over", @"on", @"into" ],
            @"see" : @[ @"the", @"if", @"what", @"how", @"it", @"that", @"you", @"this", @"any", @"a" ],
            @"take" : @[ @"a", @"the", @"it", @"care", @"into", @"some", @"this", @"time", @"place", @"note" ],
            @"look" : @[ @"at", @"like", @"for", @"into", @"forward", @"good", @"up", @"great", @"through", @"back" ],
            @"come" : @[ @"back", @"up", @"from", @"to", @"in", @"out", @"with", @"across", @"through", @"along" ],
            @"give" : @[ @"me", @"it", @"you", @"a", @"the", @"up", @"them", @"us", @"this", @"some" ],
            @"use" : @[ @"the", @"a", @"it", @"this", @"that", @"of", @"to", @"case", @"cases", @"your" ],
            @"find" : @[ @"the", @"a", @"out", @"it", @"that", @"this", @"any", @"what", @"some", @"more" ],
            @"tell" : @[ @"me", @"you", @"us", @"them", @"him", @"her", @"the", @"if", @"what", @"about" ],
            @"work" : @[ @"on", @"with", @"for", @"in", @"out", @"well", @"together", @"around", @"through", @"fine" ],
            @"try" : @[ @"to", @"it", @"again", @"the", @"a", @"this", @"that", @"something", @"using", @"running" ],
            @"keep" : @[ @"it", @"the", @"in", @"up", @"going", @"track", @"an", @"your", @"a", @"them" ],
            @"let" : @[ @"me", @"us", @"it", @"the", @"them", @"him", @"her", @"you", @"that", @"this" ],
            @"run" : @[ @"the", @"a", @"it", @"this", @"into", @"out", @"tests", @"again", @"on", @"with" ],
            @"set" : @[ @"up", @"the", @"a", @"it", @"to", @"of", @"this", @"that", @"your", @"our" ],
            @"add" : @[ @"a", @"the", @"it", @"this", @"to", @"more", @"some", @"new", @"an", @"another" ],
            @"create" : @[ @"a", @"the", @"an", @"new", @"your", @"this", @"our", @"it", @"one", @"more" ],
            @"update" : @[ @"the", @"your", @"it", @"this", @"our", @"a", @"all", @"any", @"my", @"each" ],
            @"check" : @[ @"the", @"if", @"out", @"it", @"your", @"this", @"that", @"for", @"whether", @"with" ],
            @"send" : @[ @"a", @"the", @"it", @"me", @"you", @"an", @"this", @"them", @"us", @"your" ],
            @"start" : @[ @"with", @"the", @"a", @"by", @"from", @"working", @"building", @"using", @"doing", @"over" ],
            @"move" : @[ @"to", @"the", @"on", @"forward", @"it", @"this", @"into", @"from", @"out", @"up" ],
            @"change" : @[ @"the", @"it", @"this", @"your", @"my", @"that", @"to", @"in", @"how", @"anything" ],
            @"write" : @[ @"a", @"the", @"it", @"this", @"code", @"to", @"an", @"about", @"down", @"some" ],
            @"read" : @[ @"the", @"a", @"it", @"this", @"about", @"more", @"through", @"from", @"that", @"my" ],
            @"open" : @[ @"the", @"a", @"it", @"source", @"up", @"an", @"this", @"your", @"to", @"and" ],
            @"close" : @[ @"the", @"it", @"to", @"this", @"a", @"your", @"that", @"enough", @"down", @"up" ],
            @"build" : @[ @"a", @"the", @"it", @"on", @"up", @"this", @"an", @"your", @"our", @"and" ],
            @"fix" : @[ @"the", @"it", @"this", @"a", @"that", @"any", @"your", @"some", @"bug", @"issue" ],
            @"test" : @[ @"the", @"it", @"this", @"that", @"if", @"your", @"with", @"for", @"case", @"cases" ],
            // Negation
            @"not" : @[ @"be", @"have", @"only", @"just", @"want", @"know", @"need", @"think", @"sure", @"yet", @"working", @"going", @"the", @"a", @"supported" ],
            // Conjunctions & connectors
            @"and" : @[ @"the", @"a", @"it", @"I", @"he", @"she", @"we", @"they", @"then", @"that", @"this", @"also", @"all", @"other", @"more" ],
            @"but" : @[ @"I", @"it", @"the", @"that", @"this", @"we", @"he", @"she", @"they", @"you", @"not", @"also", @"still", @"if", @"there" ],
            @"or" : @[ @"the", @"a", @"any", @"other", @"else", @"not", @"you", @"we", @"it", @"if", @"even", @"just", @"more", @"something", @"anything" ],
            @"if" : @[ @"you", @"the", @"it", @"we", @"they", @"I", @"there", @"this", @"that", @"not", @"possible", @"anyone", @"any", @"so", @"a" ],
            @"so" : @[ @"I", @"that", @"the", @"it", @"we", @"you", @"much", @"many", @"far", @"much", @"what", @"this", @"long", @"let", @"just" ],
            @"when" : @[ @"you", @"I", @"the", @"it", @"we", @"they", @"he", @"she", @"a", @"this", @"that", @"there", @"using", @"running", @"working" ],
            @"where" : @[ @"the", @"you", @"I", @"it", @"we", @"they", @"is", @"are", @"do", @"did", @"to", @"a", @"this", @"there", @"can" ],
            @"while" : @[ @"the", @"I", @"it", @"we", @"they", @"this", @"that", @"there", @"still", @"also", @"working", @"running", @"doing", @"using", @"being" ],
            @"because" : @[ @"it", @"the", @"of", @"I", @"we", @"they", @"he", @"she", @"this", @"that", @"there", @"you", @"our", @"my", @"their" ],
            @"then" : @[ @"the", @"it", @"I", @"we", @"you", @"he", @"she", @"they", @"this", @"that", @"a", @"we", @"use", @"run", @"try" ],
            @"also" : @[ @"be", @"have", @"need", @"want", @"a", @"the", @"use", @"add", @"check", @"make", @"see", @"try", @"include", @"note", @"consider" ],
            @"just" : @[ @"a", @"the", @"to", @"like", @"use", @"need", @"want", @"one", @"be", @"in", @"about", @"had", @"got", @"started", @"wondering" ],
            @"still" : @[ @"have", @"be", @"not", @"need", @"a", @"the", @"working", @"waiting", @"looking", @"trying", @"here", @"going", @"in", @"get", @"want" ],
            @"already" : @[ @"have", @"been", @"has", @"had", @"done", @"know", @"existing", @"mentioned", @"installed", @"started", @"set", @"in", @"a", @"the", @"using" ],
            // Prepositions
            @"with" : @[ @"the", @"a", @"this", @"that", @"his", @"her", @"their", @"our", @"my", @"your", @"it", @"an", @"some", @"no", @"any" ],
            @"for" : @[ @"the", @"a", @"this", @"that", @"all", @"any", @"each", @"every", @"more", @"some", @"your", @"example", @"now", @"me", @"it" ],
            @"in" : @[ @"the", @"a", @"this", @"that", @"order", @"which", @"some", @"any", @"our", @"my", @"your", @"general", @"fact", @"case", @"terms" ],
            @"on" : @[ @"the", @"a", @"this", @"that", @"my", @"his", @"her", @"their", @"our", @"your", @"it", @"top", @"how", @"what", @"time" ],
            @"to" : @[ @"be", @"the", @"do", @"get", @"make", @"have", @"go", @"see", @"take", @"find", @"use", @"add", @"create", @"check", @"set" ],
            @"of" : @[ @"the", @"a", @"this", @"that", @"his", @"her", @"their", @"our", @"my", @"its", @"it", @"all", @"course", @"them", @"any" ],
            @"from" : @[ @"the", @"a", @"this", @"that", @"here", @"there", @"my", @"your", @"our", @"their", @"scratch", @"now", @"what", @"where", @"which" ],
            @"at" : @[ @"the", @"a", @"this", @"that", @"least", @"all", @"first", @"once", @"any", @"some", @"it", @"home", @"work", @"runtime", @"compile" ],
            @"by" : @[ @"the", @"a", @"this", @"that", @"default", @"using", @"adding", @"running", @"checking", @"creating", @"setting", @"doing", @"now", @"design", @"far" ],
            @"about" : @[ @"the", @"it", @"this", @"that", @"how", @"what", @"a", @"your", @"our", @"my", @"them", @"us", @"whether", @"anything", @"something" ],
            @"into" : @[ @"the", @"a", @"this", @"that", @"it", @"account", @"consideration", @"your", @"our", @"an", @"play", @"more", @"detail", @"place", @"practice" ],
            @"after" : @[ @"the", @"a", @"that", @"this", @"all", @"each", @"every", @"it", @"you", @"we", @"running", @"finishing", @"completing", @"calling", @"using" ],
            @"before" : @[ @"the", @"it", @"you", @"we", @"I", @"that", @"this", @"a", @"any", @"running", @"starting", @"calling", @"doing", @"using", @"making" ],
            @"between" : @[ @"the", @"a", @"two", @"different", @"these", @"them", @"us", @"multiple", @"various", @"each" ],
            @"through" : @[ @"the", @"a", @"this", @"it", @"all", @"each", @"our", @"your", @"their", @"an" ],
            // Question words
            @"what" : @[ @"is", @"are", @"was", @"do", @"does", @"would", @"can", @"about", @"if", @"kind", @"the", @"you", @"we", @"should", @"I" ],
            @"how" : @[ @"are", @"do", @"does", @"can", @"is", @"was", @"about", @"much", @"many", @"long", @"to", @"would", @"should", @"it", @"often" ],
            @"why" : @[ @"is", @"are", @"do", @"does", @"did", @"would", @"not", @"was", @"the", @"this", @"it", @"don't", @"should", @"can't", @"I" ],
            @"who" : @[ @"is", @"are", @"was", @"were", @"has", @"have", @"will", @"would", @"can", @"does", @"the", @"this", @"else", @"you", @"I" ],
            @"which" : @[ @"is", @"are", @"was", @"will", @"would", @"can", @"means", @"one", @"I", @"we", @"you", @"the", @"should", @"may", @"might" ],
            // Common greetings / phrases
            @"hello" : @[ @"world", @"there", @"everyone", @"how", @"my", @"and", @"again", @"from", @"I'm", @"team" ],
            @"hi" : @[ @"there", @"everyone", @"team", @"all", @"I'm", @"how", @"thanks", @"sorry", @"just", @"I" ],
            @"good" : @[ @"morning", @"evening", @"afternoon", @"night", @"luck", @"idea", @"job", @"news", @"time", @"work", @"point", @"question", @"choice", @"example", @"day" ],
            @"thank" : @[ @"you", @"goodness", @"god", @"everyone", @"them", @"her", @"him" ],
            @"thanks" : @[ @"for", @"to", @"so", @"again", @"a", @"everyone", @"very", @"I", @"that", @"in" ],
            @"please" : @[ @"let", @"help", @"send", @"tell", @"give", @"make", @"note", @"check", @"try", @"do", @"feel", @"don't", @"see", @"find", @"ensure" ],
            @"sorry" : @[ @"for", @"about", @"I", @"to", @"but", @"if", @"that", @"the", @"this", @"we" ],
            // Adjectives / adverbs
            @"very" : @[ @"much", @"good", @"well", @"nice", @"important", @"interesting", @"happy", @"sorry", @"different", @"useful", @"helpful", @"easy", @"simple", @"similar", @"common" ],
            @"more" : @[ @"than", @"about", @"information", @"details", @"or", @"specific", @"important", @"likely", @"complex", @"efficient", @"of", @"time", @"work", @"data", @"context" ],
            @"most" : @[ @"of", @"likely", @"important", @"common", @"cases", @"people", @"the", @"recent", @"popular", @"useful", @"effective", @"efficient", @"relevant", @"basic", @"obvious" ],
            @"really" : @[ @"good", @"well", @"like", @"want", @"need", @"appreciate", @"helpful", @"important", @"nice", @"great", @"hope", @"think", @"happy", @"sorry", @"hard" ],
            @"too" : @[ @"much", @"many", @"long", @"late", @"early", @"bad", @"big", @"small", @"fast", @"slow", @"hard", @"often", @"far", @"large", @"complex" ],
            @"only" : @[ @"the", @"a", @"one", @"way", @"thing", @"if", @"when", @"to", @"for", @"in", @"works", @"need", @"available", @"applies", @"takes" ],
            @"even" : @[ @"if", @"though", @"more", @"the", @"a", @"when", @"better", @"after", @"before", @"with", @"in", @"without", @"further", @"now", @"then" ],
            @"new" : @[ @"one", @"version", @"feature", @"file", @"way", @"project", @"line", @"branch", @"issue", @"update", @"data", @"code", @"approach", @"release", @"changes" ],
            // Tech / coding context
            @"code" : @[ @"is", @"that", @"for", @"in", @"to", @"and", @"review", @"change", @"changes", @"base", @"works", @"should", @"needs", @"looks", @"was" ],
            @"file" : @[ @"is", @"and", @"to", @"in", @"for", @"that", @"was", @"with", @"has", @"should", @"already", @"path", @"name", @"not", @"system" ],
            @"data" : @[ @"is", @"from", @"to", @"in", @"for", @"and", @"that", @"was", @"will", @"can", @"should", @"has", @"into", @"with", @"structure" ],
            @"error" : @[ @"is", @"in", @"when", @"message", @"handling", @"was", @"occurred", @"that", @"code", @"and", @"with", @"for", @"on", @"from", @"during" ],
            @"function" : @[ @"that", @"to", @"is", @"in", @"for", @"and", @"returns", @"takes", @"which", @"should", @"can", @"will", @"was", @"called", @"call" ],
            @"class" : @[ @"that", @"is", @"for", @"in", @"and", @"to", @"with", @"which", @"has", @"should", @"can", @"will", @"was", @"called", @"method" ],
            @"method" : @[ @"that", @"is", @"to", @"for", @"in", @"and", @"returns", @"takes", @"which", @"should", @"can", @"will", @"was", @"called", @"call" ],
            @"value" : @[ @"is", @"of", @"for", @"in", @"to", @"and", @"that", @"was", @"will", @"should", @"can", @"from", @"with", @"as", @"or" ],
            @"type" : @[ @"is", @"of", @"for", @"in", @"to", @"and", @"that", @"was", @"should", @"can", @"error", @"checking", @"annotation", @"system", @"parameter" ],
            @"list" : @[ @"of", @"is", @"and", @"for", @"in", @"to", @"that", @"with", @"all", @"the", @"items", @"here", @"below", @"above", @"contains" ],
            // "there" and existential
            @"there" : @[ @"is", @"are", @"was", @"were", @"will", @"should", @"might", @"could", @"may", @"would", @"any", @"a", @"no", @"have", @"has" ],
            // "going"
            @"going" : @[ @"to", @"forward", @"on", @"well", @"through", @"back", @"ahead", @"into", @"out", @"wrong" ],
            // "looking"
            @"looking" : @[ @"for", @"at", @"into", @"forward", @"good", @"like", @"to", @"great", @"through", @"back" ],
            // Common phrase starters
            @"let's" : @[ @"go", @"see", @"start", @"try", @"do", @"say", @"make", @"talk", @"move", @"keep", @"look", @"check", @"get", @"take", @"use" ],
            @"i'm" : @[ @"not", @"going", @"looking", @"trying", @"working", @"sorry", @"sure", @"here", @"wondering", @"happy", @"afraid", @"glad", @"just", @"a", @"the" ],
            @"it's" : @[ @"not", @"a", @"the", @"just", @"been", @"going", @"important", @"possible", @"better", @"hard", @"easy", @"time", @"worth", @"more", @"really" ],
            @"that's" : @[ @"a", @"the", @"right", @"great", @"good", @"fine", @"why", @"what", @"how", @"not", @"true", @"correct", @"exactly", @"interesting", @"it" ],
            @"there's" : @[ @"a", @"no", @"an", @"the", @"nothing", @"something", @"also", @"always", @"still", @"already", @"been", @"one", @"only", @"another", @"more" ],
            @"here's" : @[ @"the", @"a", @"an", @"what", @"how", @"my", @"our", @"one", @"another", @"your" ],
            @"i've" : @[ @"been", @"never", @"already", @"just", @"also", @"got", @"had", @"seen", @"tried", @"done", @"found", @"heard", @"made", @"used", @"noticed" ],
            @"we're" : @[ @"going", @"looking", @"trying", @"working", @"not", @"here", @"done", @"all", @"happy", @"planning", @"using", @"building", @"running", @"still", @"almost" ],
            @"you're" : @[ @"right", @"welcome", @"looking", @"going", @"not", @"using", @"trying", @"working", @"done", @"sure", @"here", @"the", @"a", @"running", @"saying" ],
        };

        // Trigrams: "word1 word2" -> likely next words
        _mockTrigrams = @{
            @"i am" : @[ @"not", @"a", @"going", @"looking", @"trying", @"working", @"sure", @"here", @"happy", @"sorry" ],
            @"i have" : @[ @"been", @"to", @"a", @"the", @"not", @"no", @"some", @"already", @"never", @"just" ],
            @"i think" : @[ @"that", @"it", @"the", @"we", @"this", @"so", @"you", @"I", @"about", @"there" ],
            @"i want" : @[ @"to", @"it", @"the", @"a", @"that", @"this", @"you", @"something", @"more", @"my" ],
            @"i will" : @[ @"be", @"have", @"try", @"do", @"get", @"make", @"take", @"check", @"send", @"look" ],
            @"i need" : @[ @"to", @"a", @"the", @"more", @"some", @"it", @"this", @"your", @"help", @"time" ],
            @"i would" : @[ @"like", @"say", @"suggest", @"recommend", @"prefer", @"appreciate", @"love", @"think", @"be", @"have" ],
            @"i don't" : @[ @"know", @"think", @"want", @"have", @"need", @"understand", @"see", @"like", @"mind", @"care" ],
            @"i can" : @[ @"see", @"help", @"do", @"try", @"make", @"use", @"get", @"take", @"find", @"also" ],
            @"you can" : @[ @"use", @"also", @"try", @"find", @"see", @"do", @"check", @"get", @"run", @"add" ],
            @"you are" : @[ @"right", @"welcome", @"looking", @"going", @"not", @"using", @"the", @"a", @"here", @"sure" ],
            @"you have" : @[ @"to", @"a", @"the", @"been", @"any", @"not", @"already", @"no", @"some", @"it" ],
            @"we can" : @[ @"use", @"also", @"try", @"do", @"make", @"add", @"see", @"get", @"start", @"check" ],
            @"we have" : @[ @"to", @"a", @"the", @"been", @"already", @"no", @"not", @"some", @"it", @"this" ],
            @"we need" : @[ @"to", @"a", @"the", @"more", @"some", @"it", @"this", @"your", @"our", @"another" ],
            @"we should" : @[ @"also", @"be", @"have", @"use", @"add", @"consider", @"make", @"try", @"check", @"not" ],
            @"it is" : @[ @"not", @"a", @"the", @"possible", @"important", @"also", @"just", @"very", @"still", @"worth" ],
            @"it was" : @[ @"not", @"a", @"the", @"very", @"just", @"also", @"still", @"quite", @"actually", @"really" ],
            @"it will" : @[ @"be", @"not", @"take", @"work", @"help", @"also", @"make", @"give", @"cause", @"show" ],
            @"it would" : @[ @"be", @"have", @"make", @"take", @"help", @"seem", @"look", @"mean", @"work", @"also" ],
            @"it can" : @[ @"be", @"also", @"help", @"cause", @"take", @"make", @"lead", @"work", @"handle", @"only" ],
            @"there is" : @[ @"a", @"no", @"an", @"the", @"also", @"nothing", @"something", @"one", @"only", @"already" ],
            @"there are" : @[ @"no", @"many", @"some", @"several", @"a", @"two", @"three", @"also", @"other", @"different" ],
            @"this is" : @[ @"a", @"the", @"not", @"an", @"because", @"how", @"what", @"where", @"why", @"expected" ],
            @"this will" : @[ @"be", @"not", @"help", @"make", @"allow", @"cause", @"also", @"give", @"take", @"work" ],
            @"that is" : @[ @"not", @"a", @"the", @"why", @"how", @"what", @"because", @"exactly", @"correct", @"true" ],
            @"how to" : @[ @"use", @"do", @"get", @"make", @"fix", @"add", @"create", @"set", @"run", @"build" ],
            @"how do" : @[ @"you", @"I", @"we", @"they", @"these", @"those" ],
            @"want to" : @[ @"do", @"make", @"get", @"be", @"know", @"see", @"use", @"add", @"try", @"go" ],
            @"need to" : @[ @"be", @"do", @"make", @"get", @"have", @"add", @"use", @"check", @"create", @"update" ],
            @"going to" : @[ @"be", @"do", @"have", @"make", @"get", @"try", @"use", @"need", @"take", @"work" ],
            @"able to" : @[ @"do", @"get", @"see", @"use", @"make", @"find", @"help", @"work", @"run", @"access" ],
            @"have to" : @[ @"do", @"be", @"make", @"use", @"get", @"go", @"take", @"deal", @"manually", @"wait" ],
            @"try to" : @[ @"do", @"make", @"get", @"find", @"use", @"keep", @"be", @"avoid", @"fix", @"understand" ],
            @"used to" : @[ @"be", @"do", @"have", @"make", @"get", @"work", @"store", @"track", @"define", @"represent" ],
            @"like to" : @[ @"know", @"see", @"have", @"add", @"use", @"make", @"do", @"get", @"thank", @"suggest" ],
            @"sure to" : @[ @"check", @"include", @"add", @"update", @"use", @"follow", @"test", @"read", @"run", @"review" ],
            @"make sure" : @[ @"that", @"the", @"you", @"to", @"it", @"we", @"everything", @"all", @"your", @"this" ],
            @"as well" : @[ @"as", @"and", @"but", @"for", @"in", @"so", @"the", @"which", @"that", @"when" ],
            @"so that" : @[ @"the", @"it", @"we", @"you", @"they", @"I", @"this", @"there", @"each", @"all" ],
            @"in order" : @[ @"to", @"for", @"of" ],
            @"such as" : @[ @"the", @"a", @"an", @"this", @"using", @"adding", @"creating", @"running", @"when", @"if" ],
            @"look at" : @[ @"the", @"it", @"this", @"that", @"how", @"what", @"your", @"our", @"a", @"some" ],
            @"look for" : @[ @"the", @"a", @"it", @"any", @"this", @"that", @"an", @"ways", @"something", @"patterns" ],
            @"look like" : @[ @"a", @"the", @"this", @"it", @"they", @"an", @"something", @"what", @"that", @"one" ],
            @"think about" : @[ @"it", @"the", @"this", @"that", @"what", @"how", @"whether", @"your", @"our", @"a" ],
            @"talk about" : @[ @"it", @"the", @"this", @"that", @"what", @"how", @"your", @"our", @"a", @"some" ],
            @"come up" : @[ @"with", @"in", @"again", @"to", @"and", @"here", @"yet", @"often", @"later", @"before" ],
            @"end up" : @[ @"with", @"in", @"being", @"having", @"doing", @"using", @"getting", @"making", @"losing", @"spending" ],
            @"set up" : @[ @"the", @"a", @"your", @"an", @"our", @"this", @"to", @"for", @"and", @"correctly" ],
            @"pick up" : @[ @"the", @"a", @"on", @"where", @"some", @"this", @"from", @"your", @"speed", @"steam" ],
            @"based on" : @[ @"the", @"your", @"this", @"that", @"our", @"my", @"what", @"how", @"a", @"their" ],
            @"due to" : @[ @"the", @"a", @"an", @"this", @"that", @"its", @"their", @"our", @"some", @"various" ],
            @"instead of" : @[ @"using", @"the", @"a", @"just", @"having", @"doing", @"creating", @"adding", @"making", @"this" ],
            @"kind of" : @[ @"like", @"a", @"the", @"thing", @"way", @"hard", @"weird", @"strange", @"expected", @"makes" ],
            @"out of" : @[ @"the", @"it", @"order", @"memory", @"range", @"scope", @"date", @"sync", @"bounds", @"context" ],
            @"a lot" : @[ @"of", @"more", @"about", @"like", @"better", @"easier", @"faster", @"harder", @"less", @"to" ],
            @"one of" : @[ @"the", @"those", @"these", @"them", @"my", @"our", @"your", @"its", @"his", @"her" ],
            @"each of" : @[ @"the", @"these", @"those", @"them", @"which", @"us", @"you" ],
            @"thank you" : @[ @"for", @"so", @"very", @"again", @"I", @"and", @"all", @"everyone", @"both", @"in" ],
            @"good morning" : @[ @"everyone", @"team", @"I", @"how", @"and", @"hope", @"happy", @"we", @"just", @"thanks" ],
            @"good afternoon" : @[ @"everyone", @"team", @"I", @"how", @"and", @"hope", @"happy", @"we", @"just", @"thanks" ],
            @"good evening" : @[ @"everyone", @"team", @"I", @"how", @"and", @"hope", @"happy", @"we", @"just", @"thanks" ],
        };
    });
}

@interface NextWordPredictor () <NSURLSessionDownloadDelegate> {
#if HALLELUJAH_USE_LLAMA
    struct llama_model *_model;
    struct llama_context *_ctx;
#endif
    dispatch_queue_t _inferenceQueue;
    dispatch_queue_t _syncQueue;
    BOOL _cancelled;
    NSDictionary *_mockWordData; // word frequency data for mock mode
    NSDictionary *_wordDictionary; // full word dictionary for LLM prediction filtering

    // Cached ordered word list from the last LLM inference (best first)
    NSArray<NSString *> *_cachedRankedWords;
    NSString *_cachedContextKey;
}

@property(nonatomic, readwrite) BOOL isModelLoaded;
@property(nonatomic, readwrite) LLMModelTier currentTier;
@property(nonatomic, readwrite) BOOL isMockMode;
@property(nonatomic, readwrite) BOOL isDownloadingModel;
@property(nonatomic, readwrite) double downloadProgress;
@property(nonatomic, readwrite) LLMModelTier downloadingTier;
@property(nonatomic, readwrite, copy, nullable) NSString *downloadStatus;
@property(nonatomic, strong, nullable) NSURLSession *downloadSession;
@property(nonatomic, strong, nullable) NSURLSessionDownloadTask *downloadTask;
@property(nonatomic, copy, nullable) void (^downloadCompletionHandler)(BOOL success, NSError *error);
@property(nonatomic, readwrite) BOOL downloadMoveCompleted;
@property(nonatomic, strong, nullable) NSError *downloadTerminalError;

@end

@implementation NextWordPredictor

+ (instancetype)shared {
    static NextWordPredictor *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[NextWordPredictor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
#if HALLELUJAH_USE_LLAMA
        _model = NULL;
        _ctx = NULL;
#endif
        _isModelLoaded = NO;
        _isMockMode = NO;
        _currentTier = LLMModelTierSmall;
        _downloadingTier = LLMModelTierSmall;
        _cancelled = NO;
        _mockWordData = nil;
        _inferenceQueue = dispatch_queue_create("com.typeflow.inference", DISPATCH_QUEUE_SERIAL);
        _syncQueue = dispatch_queue_create("com.typeflow.predictor.sync", DISPATCH_QUEUE_SERIAL);
        initMockBigrams();
        initCommonEnglishWords();
    }
    return self;
}

- (void)dealloc {
    [self.downloadSession invalidateAndCancel];
    [self unloadModel];
}

#pragma mark - Model Directory

+ (NSString *)modelDirectoryPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *appSupport = paths.firstObject;
    return [[appSupport stringByAppendingPathComponent:kAppSupportDir] stringByAppendingPathComponent:kModelDirName];
}

+ (NSString *)modelFilenameForTier:(LLMModelTier)tier {
    switch (tier) {
    case LLMModelTierSmall:
        return kModelFileSmall;
    case LLMModelTierMedium:
        return kModelFileMedium;
    case LLMModelTierLarge:
        return kModelFileLarge;
    case LLMModelTierXLarge:
        return kModelFileXLarge;
    }
    return kModelFileSmall;
}

+ (BOOL)isModelAvailableForTier:(LLMModelTier)tier {
    NSString *path = [[self modelDirectoryPath] stringByAppendingPathComponent:[self modelFilenameForTier:tier]];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (NSString *)modelPathForTier:(LLMModelTier)tier {
    return [[self modelDirectoryPath] stringByAppendingPathComponent:[self modelFilenameForTier:tier]];
}

+ (NSString *)modelDisplayNameForTier:(LLMModelTier)tier {
    switch (tier) {
    case LLMModelTierSmall:
        return @"Small";
    case LLMModelTierMedium:
        return @"Medium";
    case LLMModelTierLarge:
        return @"Large";
    case LLMModelTierXLarge:
        return @"XLarge";
    }
    return @"Small";
}

+ (NSString *)modelDownloadURLStringForTier:(LLMModelTier)tier {
    switch (tier) {
    case LLMModelTierSmall:
        return kModelURLSmall;
    case LLMModelTierMedium:
        return kModelURLMedium;
    case LLMModelTierLarge:
        return kModelURLLarge;
    case LLMModelTierXLarge:
        return kModelURLXLarge;
    }
    return kModelURLSmall;
}

#pragma mark - Model Download

- (BOOL)downloadModelForTier:(LLMModelTier)tier
                       error:(NSError **)error
                  completion:(void (^)(BOOL success, NSError *error))completion {
    NSString *downloadURLString = [NextWordPredictor modelDownloadURLStringForTier:tier];
    NSString *tierName = [NextWordPredictor modelDisplayNameForTier:tier];
    NSString *modelDirectory = [NextWordPredictor modelDirectoryPath];

    if ([NextWordPredictor isModelAvailableForTier:tier]) {
        self.downloadingTier = tier;
        self.downloadProgress = 1.0;
        self.downloadStatus = [NSString stringWithFormat:@"%@ model is already downloaded.", tierName];
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES, nil);
            });
        }
        return YES;
    }

    @synchronized(self) {
        if (self.isDownloadingModel) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"%@ model is already downloading.",
                                                               [NextWordPredictor modelDisplayNameForTier:self.downloadingTier]];
                *error = [NSError errorWithDomain:@"NextWordPredictor"
                                             code:20
                                         userInfo:@{NSLocalizedDescriptionKey : message}];
            }
            return NO;
        }

        NSError *directoryError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:modelDirectory
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&directoryError]) {
            if (error) {
                *error = directoryError;
            }
            return NO;
        }

        NSURL *downloadURL = [NSURL URLWithString:downloadURLString];
        if (!downloadURL) {
            if (error) {
                *error = [NSError errorWithDomain:@"NextWordPredictor"
                                             code:21
                                         userInfo:@{NSLocalizedDescriptionKey : @"Model download URL is invalid."}];
            }
            return NO;
        }

        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.timeoutIntervalForRequest = 60.0;
        configuration.timeoutIntervalForResource = 60.0 * 60.0 * 6.0;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

        self.isDownloadingModel = YES;
        self.downloadProgress = 0.0;
        self.downloadingTier = tier;
        self.downloadStatus = [NSString stringWithFormat:@"Preparing %@ model download...", tierName];
        self.downloadCompletionHandler = [completion copy];
        self.downloadMoveCompleted = NO;
        self.downloadTerminalError = nil;
        self.downloadSession = [NSURLSession sessionWithConfiguration:configuration
                                                             delegate:self
                                                        delegateQueue:[NSOperationQueue mainQueue]];
        self.downloadTask = [self.downloadSession downloadTaskWithURL:downloadURL];
        [self.downloadTask resume];
    }

    return YES;
}

- (void)_finishDownloadWithSuccess:(BOOL)success error:(NSError *)error {
    void (^completion)(BOOL success, NSError *error) = nil;
    NSURLSession *session = nil;
    LLMModelTier tier = self.downloadingTier;
    NSString *tierName = [NextWordPredictor modelDisplayNameForTier:tier];

    @synchronized(self) {
        completion = [self.downloadCompletionHandler copy];
        session = self.downloadSession;
        self.downloadCompletionHandler = nil;
        self.downloadSession = nil;
        self.downloadTask = nil;
        self.isDownloadingModel = NO;
        self.downloadProgress = success ? 1.0 : 0.0;
        self.downloadStatus = success ? [NSString stringWithFormat:@"%@ model downloaded and ready.", tierName]
                                      : error.localizedDescription;
        self.downloadMoveCompleted = NO;
        self.downloadTerminalError = nil;
    }

    [session finishTasksAndInvalidate];

    if (completion) {
        completion(success, error);
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didWriteData:(int64_t)bytesWritten
totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    @synchronized(self) {
        if (session != self.downloadSession || downloadTask != self.downloadTask) {
            return;
        }

        NSString *tierName = [NextWordPredictor modelDisplayNameForTier:self.downloadingTier];
        if (totalBytesExpectedToWrite > 0) {
            self.downloadProgress = (double)totalBytesWritten / (double)totalBytesExpectedToWrite;
            NSInteger percent = (NSInteger)llround(self.downloadProgress * 100.0);
            self.downloadStatus = [NSString stringWithFormat:@"Downloading %@ model... %ld%%", tierName, (long)percent];
        } else {
            self.downloadStatus = [NSString stringWithFormat:@"Downloading %@ model...", tierName];
        }
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    @synchronized(self) {
        if (session != self.downloadSession || downloadTask != self.downloadTask) {
            return;
        }

        NSHTTPURLResponse *response = (NSHTTPURLResponse *)downloadTask.response;
        if ([response isKindOfClass:[NSHTTPURLResponse class]] && response.statusCode >= 400) {
            self.downloadTerminalError = [NSError errorWithDomain:@"NextWordPredictor"
                                                             code:22
                                                         userInfo:@{NSLocalizedDescriptionKey :
                                                                        [NSString stringWithFormat:@"Model download failed (HTTP %ld).",
                                                                                                   (long)response.statusCode]}];
            return;
        }

        NSString *destinationPath = [NextWordPredictor modelPathForTier:self.downloadingTier];
        NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];
        NSFileManager *fileManager = [NSFileManager defaultManager];

        [fileManager removeItemAtURL:destinationURL error:nil];

        NSError *moveError = nil;
        if (![fileManager moveItemAtURL:location toURL:destinationURL error:&moveError]) {
            self.downloadTerminalError = moveError;
            return;
        }

        self.downloadMoveCompleted = YES;
        self.downloadProgress = 1.0;
        self.downloadStatus = [NSString stringWithFormat:@"Installing %@ model...",
                                                         [NextWordPredictor modelDisplayNameForTier:self.downloadingTier]];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSError *terminalError = nil;
    BOOL moveCompleted = NO;

    @synchronized(self) {
        if (session != self.downloadSession || task != self.downloadTask) {
            return;
        }
        terminalError = error ?: self.downloadTerminalError;
        moveCompleted = self.downloadMoveCompleted;
    }

    if (!terminalError && !moveCompleted) {
        terminalError = [NSError errorWithDomain:@"NextWordPredictor"
                                            code:23
                                        userInfo:@{NSLocalizedDescriptionKey : @"Model download did not complete successfully."}];
    }

    [self _finishDownloadWithSuccess:(terminalError == nil) error:terminalError];
}

#pragma mark - Mock Mode

- (void)enableMockModeWithWordData:(NSDictionary *)wordData {
    dispatch_sync(_inferenceQueue, ^{
        self->_mockWordData = wordData;
        dispatch_sync(self->_syncQueue, ^{
            self.isMockMode = YES;
            self.isModelLoaded = YES;
        });
        NSLog(@"[NextWordPredictor] Mock mode enabled with %lu words", (unsigned long)wordData.count);
    });
}

- (void)setWordDictionary:(NSDictionary *)wordData {
    dispatch_sync(_syncQueue, ^{
        self->_wordDictionary = wordData;
    });
    NSLog(@"[NextWordPredictor] Word dictionary set with %lu words", (unsigned long)wordData.count);
}

- (NSArray<NSString *> *)_mockPredict:(NSString *)context count:(NSInteger)count {
    // Extract last two words from context for trigram + bigram lookup
    NSArray *words = [context componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *cleanWords = [NSMutableArray array];
    for (NSString *w in words) {
        if (w.length > 0) {
            [cleanWords addObject:w.lowercaseString];
        }
    }

    if (cleanWords.count == 0)
        return @[];

    NSString *lastWord = cleanWords.lastObject;
    NSString *secondLastWord = cleanWords.count >= 2 ? cleanWords[cleanWords.count - 2] : nil;

    NSMutableArray<NSString *> *results = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    // Strategy 1: Check trigram table (highest priority - more context = better predictions)
    if (secondLastWord) {
        NSString *trigramKey = [NSString stringWithFormat:@"%@ %@", secondLastWord, lastWord];
        NSArray<NSString *> *trigramSuggestions = _mockTrigrams[trigramKey];
        if (trigramSuggestions) {
            for (NSString *word in trigramSuggestions) {
                if ((int)results.count >= count)
                    break;
                if (![seen containsObject:word.lowercaseString]) {
                    [seen addObject:word.lowercaseString];
                    [results addObject:word];
                }
            }
        }
    }

    // Strategy 2: Check bigram table
    if ((int)results.count < count) {
        NSArray<NSString *> *bigramSuggestions = _mockBigrams[lastWord];
        if (bigramSuggestions) {
            for (NSString *word in bigramSuggestions) {
                if ((int)results.count >= count)
                    break;
                if (![seen containsObject:word.lowercaseString]) {
                    [seen addObject:word.lowercaseString];
                    [results addObject:word];
                }
            }
        }
    }

    // Strategy 3: If not enough, use frequency-based common words
    if ((int)results.count < count) {
        NSArray *commonWords = @[
            @"the", @"be",   @"to",    @"of",     @"and",  @"a",    @"in",   @"that", @"have", @"it",
            @"for", @"not",  @"on",    @"with",   @"he",   @"as",   @"you",  @"do",   @"at",   @"this",
            @"but", @"his",  @"by",    @"from",   @"they", @"we",   @"say",  @"her",  @"she",  @"or",
            @"an",  @"will", @"my",    @"one",    @"all",  @"would",@"there",@"their",@"what", @"so",
            @"up",  @"out",  @"if",    @"about",  @"who",  @"get",  @"which",@"go",   @"me",   @"when",
            @"make",@"can",  @"like",  @"time",   @"no",   @"just", @"him",  @"know", @"take", @"people"
        ];

        for (NSString *word in commonWords) {
            if ((int)results.count >= count)
                break;
            if (![word isEqualToString:lastWord] && ![seen containsObject:word]) {
                [seen addObject:word];
                [results addObject:word];
            }
        }
    }

    return [results copy];
}

#pragma mark - Model Loading

- (void)loadModelForTier:(LLMModelTier)tier completion:(void (^)(BOOL, NSError *))completion {
#if HALLELUJAH_USE_LLAMA
    dispatch_async(_inferenceQueue, ^{
        [self _unloadModelSync];

        NSString *modelPath = [NextWordPredictor modelPathForTier:tier];

        if (![[NSFileManager defaultManager] fileExistsAtPath:modelPath]) {
            NSError *error = [NSError errorWithDomain:@"NextWordPredictor"
                                                 code:1
                                             userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Model file not found: %@", modelPath]}];
            NSLog(@"[NextWordPredictor] Model file not found for the selected tier");
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, error);
                });
            }
            return;
        }

        NSLog(@"[NextWordPredictor] Loading model for selected tier");

        llama_backend_init();

        struct llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = 99;

        self->_model = llama_model_load_from_file([modelPath UTF8String], model_params);
        if (!self->_model) {
            NSError *error = [NSError errorWithDomain:@"NextWordPredictor"
                                                 code:2
                                             userInfo:@{NSLocalizedDescriptionKey : @"Failed to load LLM model"}];
            NSLog(@"[NextWordPredictor] Failed to load model");
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, error);
                });
            }
            return;
        }

        int ctxSize;
        switch (tier) {
        case LLMModelTierSmall:
            ctxSize = kContextSizeSmall;
            break;
        case LLMModelTierMedium:
            ctxSize = kContextSizeMedium;
            break;
        case LLMModelTierLarge:
            ctxSize = kContextSizeLarge;
            break;
        case LLMModelTierXLarge:
            ctxSize = kContextSizeXLarge;
            break;
        }

        struct llama_context_params ctx_params = llama_context_default_params();
        ctx_params.n_ctx = ctxSize;
        ctx_params.n_batch = 256;
        ctx_params.n_threads = 4;
        ctx_params.n_threads_batch = 4;

        self->_ctx = llama_init_from_model(self->_model, ctx_params);
        if (!self->_ctx) {
            llama_model_free(self->_model);
            self->_model = NULL;
            NSError *error = [NSError errorWithDomain:@"NextWordPredictor"
                                                 code:3
                                             userInfo:@{NSLocalizedDescriptionKey : @"Failed to create LLM context"}];
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, error);
                });
            }
            return;
        }

        dispatch_sync(self->_syncQueue, ^{
            self.isModelLoaded = YES;
            self.currentTier = tier;
            self.isMockMode = NO;
        });

        NSLog(@"[NextWordPredictor] Model loaded successfully (tier: %ld)", (long)tier);

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(YES, nil);
            });
        }
    });
#else
    // Without llama.cpp, fall back to mock mode automatically
    NSLog(@"[NextWordPredictor] llama.cpp not available (HALLELUJAH_USE_LLAMA=0). Use enableMockModeWithWordData: for testing.");
    NSError *error = [NSError errorWithDomain:@"NextWordPredictor"
                                         code:10
                                     userInfo:@{NSLocalizedDescriptionKey : @"llama.cpp not compiled in. Enable HALLELUJAH_USE_LLAMA=1 or use mock mode."}];
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(NO, error);
        });
    }
#endif
}

- (void)unloadModel {
    dispatch_sync(_inferenceQueue, ^{
        [self _unloadModelSync];
    });
}

- (void)_unloadModelSync {
#if HALLELUJAH_USE_LLAMA
    if (_ctx) {
        llama_free(_ctx);
        _ctx = NULL;
    }
    if (_model) {
        llama_model_free(_model);
        _model = NULL;
    }
#endif
    _mockWordData = nil;
    dispatch_sync(_syncQueue, ^{
        self.isModelLoaded = NO;
        self.isMockMode = NO;
    });
}

#pragma mark - Prediction

- (void)cancelPendingPrediction {
    dispatch_sync(_syncQueue, ^{
        self->_cancelled = YES;
    });
}

- (void)predictNextWords:(NSString *)context count:(NSInteger)count completion:(PredictionCompletionBlock)completion {
    if (!completion)
        return;

    dispatch_sync(_syncQueue, ^{
        self->_cancelled = NO;
    });

    dispatch_async(_inferenceQueue, ^{
        __block BOOL wasCancelled = NO;
        dispatch_sync(self->_syncQueue, ^{
            wasCancelled = self->_cancelled;
        });
        if (wasCancelled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            return;
        }

        __block BOOL loaded = NO;
        __block BOOL mockMode = NO;
        dispatch_sync(self->_syncQueue, ^{
            loaded = self.isModelLoaded;
            mockMode = self.isMockMode;
        });

        if (!loaded) {
            NSLog(@"[NextWordPredictor] Model not loaded, skipping prediction");
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            return;
        }

        NSArray *predictions;
        if (mockMode) {
            predictions = [self _mockPredict:context count:count];
        } else {
#if HALLELUJAH_USE_LLAMA
            predictions = [self _runLlamaInference:context count:count];
#else
            predictions = [self _mockPredict:context count:count];
#endif
        }

        dispatch_sync(self->_syncQueue, ^{
            wasCancelled = self->_cancelled;
        });
        if (wasCancelled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(predictions);
        });
    });
}

#if HALLELUJAH_USE_LLAMA
#pragma mark - LLM Inference

// Helper: convert a token to its string piece
- (NSString *)_tokenToString:(llama_token)token_id vocab:(const struct llama_vocab *)vocab {
    char buf[256];
    int n = llama_token_to_piece(vocab, token_id, buf, sizeof(buf) - 1, 0, /* special */ false);
    if (n <= 0) return nil;
    buf[n] = '\0';
    return [NSString stringWithUTF8String:buf];
}

// Helper: check if a string is a valid English word (letters and apostrophes for contractions)
- (BOOL)_isValidWord:(NSString *)word {
    if (!word || word.length == 0) return NO;
    // Allow single-letter words "a" and "I"
    if (word.length == 1) {
        unichar ch = [word characterAtIndex:0];
        return (ch == 'a' || ch == 'A' || ch == 'i' || ch == 'I');
    }
    NSMutableCharacterSet *allowed = [[NSCharacterSet letterCharacterSet] mutableCopy];
    [allowed addCharactersInString:@"'"];
    NSCharacterSet *disallowed = [allowed invertedSet];
    return [word rangeOfCharacterFromSet:disallowed].location == NSNotFound;
}

- (NSArray<NSString *> *)_runLlamaInference:(NSString *)context count:(NSInteger)count {
    if (!_model || !_ctx)
        return nil;

    llama_memory_clear(llama_get_memory(_ctx), true);

    // Trim context to last ~500 characters to keep inference fast while providing enough context
    NSString *trimmedContext = context;
    if (trimmedContext.length > 500) {
        trimmedContext = [trimmedContext substringFromIndex:trimmedContext.length - 500];
        // Try to start at a word boundary
        NSRange spaceRange = [trimmedContext rangeOfString:@" "];
        if (spaceRange.location != NSNotFound && spaceRange.location < 50) {
            trimmedContext = [trimmedContext substringFromIndex:spaceRange.location + 1];
        }
    }

    // Add a trailing space to hint that we want a NEW word
    NSString *contextWithSpace = [trimmedContext hasSuffix:@" "] ? trimmedContext : [trimmedContext stringByAppendingString:@" "];
    const char *contextCStr = [contextWithSpace UTF8String];
    int contextLen = (int)strlen(contextCStr);

    NSLog(@"[NextWordPredictor] Running LLM inference with %d context chars", contextLen);

    const struct llama_vocab *vocab = llama_model_get_vocab(_model);
    int n_ctx = llama_n_ctx(_ctx);
    std::vector<llama_token> tokens(n_ctx);

    int n_tokens = llama_tokenize(vocab, contextCStr, contextLen, tokens.data(), (int)tokens.size(),
                                  /* add_special */ true, /* parse_special */ false);

    if (n_tokens < 0) {
        NSLog(@"[NextWordPredictor] Tokenization failed");
        return nil;
    }
    tokens.resize(n_tokens);

    // If context exceeds model window, keep only the last portion
    if (n_tokens > n_ctx - 16) {
        int offset = n_tokens - (n_ctx - 16);
        tokens.erase(tokens.begin(), tokens.begin() + offset);
        n_tokens = (int)tokens.size();
    }

    NSLog(@"[NextWordPredictor] Decoding %d tokens...", n_tokens);

    struct llama_batch batch = llama_batch_get_one(tokens.data(), n_tokens);
    int ret = llama_decode(_ctx, batch);
    if (ret != 0) {
        NSLog(@"[NextWordPredictor] Decode failed with code: %d", ret);
        return nil;
    }

    float *logits = llama_get_logits_ith(_ctx, n_tokens - 1);
    if (!logits) {
        NSLog(@"[NextWordPredictor] Failed to get logits");
        return nil;
    }

    int n_vocab = llama_vocab_n_tokens(vocab);

    // Sort top-K for selecting the best prediction results
    int topK = MIN(1000, n_vocab);
    std::vector<std::pair<float, llama_token>> candidates;
    candidates.reserve(n_vocab);
    for (int i = 0; i < n_vocab; i++) {
        candidates.push_back({logits[i], (llama_token)i});
    }
    std::partial_sort(candidates.begin(), candidates.begin() + topK, candidates.end(),
                      [](const std::pair<float, llama_token> &a, const std::pair<float, llama_token> &b) { return a.first > b.first; });

    // Build a set of words already in the context (for score demotion, not exclusion).
    NSSet<NSString *> *contextWords;
    {
        NSArray *ctxTokens = [contextWithSpace componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSMutableSet *ctxSet = [NSMutableSet set];
        for (NSString *w in ctxTokens) {
            if (w.length >= 2) {
                [ctxSet addObject:w.lowercaseString];
            }
        }
        contextWords = [ctxSet copy];
    }

    // ---- Build FULL score cache by scanning ALL vocab tokens ----
    // This ensures every single-token word has an LLM score for reranking while typing.
    // Scanning ~150K tokens takes <5ms — negligible compared to LLM inference.
    NSMutableDictionary<NSString *, NSNumber *> *scoreCache = [NSMutableDictionary dictionary];
    {
        char buf[256];
        for (int i = 0; i < n_vocab; i++) {
            if (llama_vocab_is_eog(vocab, (llama_token)i)) continue;
            if (llama_vocab_is_control(vocab, (llama_token)i)) continue;

            int len = llama_token_to_piece(vocab, (llama_token)i, buf, sizeof(buf) - 1, 0, false);
            if (len <= 0) continue;
            buf[len] = '\0';

            unsigned char firstByte = (unsigned char)buf[0];
            BOOL isWordBoundary = NO;
            int wordStart = 0;
            if (firstByte == ' ') { isWordBoundary = YES; wordStart = 1; }
            else if (len >= 2 && firstByte == 0xC4 && (unsigned char)buf[1] == 0xA0) { isWordBoundary = YES; wordStart = 2; }
            else if (len >= 3 && firstByte == 0xE2 && (unsigned char)buf[1] == 0x96 && (unsigned char)buf[2] == 0x81) { isWordBoundary = YES; wordStart = 3; }
            if (!isWordBoundary) continue;

            // Basic validity: non-empty, only letters and apostrophes
            int wordLen = len - wordStart;
            if (wordLen < 1) continue;
            BOOL valid = YES;
            for (int c = wordStart; c < len && valid; c++) {
                unsigned char ch = (unsigned char)buf[c];
                if (!isalpha(ch) && ch != '\'') valid = NO;
            }
            if (!valid) continue;

            NSString *word = [[NSString alloc] initWithBytes:buf + wordStart length:len - wordStart encoding:NSUTF8StringEncoding];
            if (!word) continue;
            NSString *lowerWord = word.lowercaseString;

            // Keep highest score for each word (first occurrence wins for duplicates)
            if (!scoreCache[lowerWord]) {
                scoreCache[lowerWord] = @(logits[i]);
            }
        }
        NSLog(@"[NextWordPredictor] Cached %lu word scores from full vocab scan", (unsigned long)scoreCache.count);
    }

    // ---- Select top predictions from top-K ----
    NSMutableArray<NSDictionary *> *scoredResults = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableArray *subwordCandidates = [NSMutableArray array];

    // Score penalty for words already in context (demote but don't exclude)
    static const float kContextWordPenalty = 8.0f;

    // Filter out non-English tokens (URLs, code artifacts, etc.)
    static NSSet *blockedWords = nil;
    static dispatch_once_t blOnce;
    dispatch_once(&blOnce, ^{
        blockedWords = [NSSet setWithArray:@[
            @"https", @"http", @"www", @"html", @"css", @"js",
            @"abc", @"xyz", @"null", @"undefined", @"var", @"int",
            @"func", @"const", @"enum", @"struct", @"void",
        ]];
    });

    // Pass 1: find word-boundary tokens that are complete dictionary words
    for (int i = 0; i < topK; i++) {
        llama_token token_id = candidates[i].second;
        float score = candidates[i].first;

        if (llama_vocab_is_eog(vocab, token_id)) continue;
        if (llama_vocab_is_control(vocab, token_id)) continue;

        NSString *piece = [self _tokenToString:token_id vocab:vocab];
        if (!piece || piece.length == 0) continue;

        unichar firstChar = [piece characterAtIndex:0];
        BOOL isWordBoundary = (firstChar == ' ' || firstChar == 0x0120 || firstChar == 0x2581);
        if (!isWordBoundary) continue;

        NSString *cleanWord = [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        cleanWord = [cleanWord stringByReplacingOccurrencesOfString:@"\u0120" withString:@""];
        cleanWord = [cleanWord stringByReplacingOccurrencesOfString:@"\u2581" withString:@""];

        if (cleanWord.length == 0) continue;

        NSString *lowerWord = cleanWord.lowercaseString;

        // Skip blocked words (code artifacts, URLs)
        if ([blockedWords containsObject:lowerWord]) continue;

        // Check if this is a complete word in the dictionary
        BOOL inDictionary = NO;
        if (_wordDictionary && _wordDictionary.count > 0) {
            inDictionary = (_wordDictionary[lowerWord] != nil);
        } else {
            inDictionary = [_commonEnglishWords containsObject:lowerWord];
        }

        if (inDictionary) {
            if ([seen containsObject:lowerWord]) continue;
            [seen addObject:lowerWord];

            // Only demote words already in context; trust LLM ranking for everything else
            float adjustedScore = score;
            if ([contextWords containsObject:lowerWord]) {
                adjustedScore -= kContextWordPenalty;
            }
            [scoredResults addObject:@{@"word": lowerWord, @"score": @(adjustedScore)}];
        } else if (lowerWord.length >= 2 && (int)subwordCandidates.count < 20) {
            // This looks like a word-boundary sub-word token (e.g., " univers")
            // Save it for Pass 2 multi-token completion
            [subwordCandidates addObject:@{
                @"piece": cleanWord,
                @"token": @(token_id),
                @"score": @(score)
            }];
        }
    }

    // Pass 2: Complete sub-word tokens into full words using greedy decoding.
    // Only accept results that exist in the dictionary.
    if (subwordCandidates.count > 0) {
        for (NSDictionary *candidate in subwordCandidates) {
            NSString *startPiece = candidate[@"piece"];

            // Re-encode context + this sub-word piece and decode forward
            llama_memory_clear(llama_get_memory(_ctx), true);

            std::string fullText = std::string([contextWithSpace UTF8String]) + std::string([startPiece.lowercaseString UTF8String]);
            std::vector<llama_token> fullTokens(n_ctx);
            int fullCount = llama_tokenize(vocab, fullText.c_str(), (int)fullText.size(),
                                           fullTokens.data(), (int)fullTokens.size(), true, false);
            if (fullCount <= 0 || fullCount > n_ctx - 8) continue;
            fullTokens.resize(fullCount);

            struct llama_batch contBatch = llama_batch_get_one(fullTokens.data(), fullCount);
            if (llama_decode(_ctx, contBatch) != 0) continue;

            NSMutableString *wordBuilder = [NSMutableString stringWithString:startPiece.lowercaseString];
            BOOL wordComplete = NO;

            for (int step = 0; step < 6 && !wordComplete; step++) {
                float *contLogits = llama_get_logits_ith(_ctx, -1);
                if (!contLogits) break;

                // Find best next token
                float bestScore = -1e9;
                llama_token bestToken = -1;
                for (int v = 0; v < n_vocab; v++) {
                    if (contLogits[v] > bestScore) {
                        bestScore = contLogits[v];
                        bestToken = (llama_token)v;
                    }
                }

                if (bestToken < 0 || llama_vocab_is_eog(vocab, bestToken)) {
                    wordComplete = YES; break;
                }

                NSString *contPiece = [self _tokenToString:bestToken vocab:vocab];
                if (!contPiece || contPiece.length == 0) break;

                unichar contFirst = [contPiece characterAtIndex:0];
                if (contFirst == ' ' || contFirst == 0x0120 || contFirst == 0x2581 ||
                    [[NSCharacterSet punctuationCharacterSet] characterIsMember:contFirst]) {
                    wordComplete = YES; break;
                }

                NSString *contClean = [contPiece stringByReplacingOccurrencesOfString:@"\u0120" withString:@""];
                contClean = [contClean stringByReplacingOccurrencesOfString:@"\u2581" withString:@""];
                NSMutableCharacterSet *allowedChars = [[NSCharacterSet letterCharacterSet] mutableCopy];
                [allowedChars addCharactersInString:@"'"];
                NSCharacterSet *disallowedChars = [allowedChars invertedSet];
                if ([contClean rangeOfCharacterFromSet:disallowedChars].location != NSNotFound) {
                    wordComplete = YES; break;
                }
                [wordBuilder appendString:contClean];

                struct llama_batch stepBatch = llama_batch_get_one(&bestToken, 1);
                if (llama_decode(_ctx, stepBatch) != 0) break;
            }

            NSString *finalWord = [wordBuilder copy];
            NSString *lowerFinal = finalWord.lowercaseString;

            if (lowerFinal.length == 0) continue;
            if ([seen containsObject:lowerFinal]) continue;

            // Must exist in dictionary
            BOOL inDict = NO;
            if (_wordDictionary && _wordDictionary.count > 0) {
                inDict = (_wordDictionary[lowerFinal] != nil);
            } else {
                inDict = [_commonEnglishWords containsObject:lowerFinal];
            }
            if (!inDict) continue;

            [seen addObject:lowerFinal];

            float adjScore = [candidate[@"score"] floatValue];
            if ([contextWords containsObject:lowerFinal]) {
                adjScore -= kContextWordPenalty;
            }
            [scoredResults addObject:@{@"word": lowerFinal, @"score": @(adjScore)}];
        }
    }

    // Sort all candidates by adjusted score (context words demoted, not excluded)
    [scoredResults sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"score"] compare:a[@"score"]];
    }];

    // Take top N results
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    for (NSDictionary *entry in scoredResults) {
        if ((int)results.count >= count) break;
        [results addObject:entry[@"word"]];
    }

    // Cache the sorted word list for reranking while typing.
    {
        NSMutableArray<NSString *> *rankedWords = [NSMutableArray array];
        for (NSDictionary *entry in scoredResults) {
            [rankedWords addObject:entry[@"word"]];
        }
        dispatch_sync(_syncQueue, ^{
            self->_cachedRankedWords = [rankedWords copy];
            self->_cachedContextKey = [trimmedContext copy];
        });
    }

    NSLog(@"[NextWordPredictor] Produced %lu predictions (cache size: %lu)",
          (unsigned long)results.count, (unsigned long)scoreCache.count);

    return [results copy];
}
#endif

#pragma mark - Contextual Candidate Scoring

- (NSDictionary<NSString *, NSNumber *> *)contextualScoresForPrefix:(NSString *)prefix
                                                            context:(NSString *)context {
    if (!prefix || prefix.length == 0) return @{};

    __block NSArray<NSString *> *rankedWords = nil;
    dispatch_sync(_syncQueue, ^{
        rankedWords = self->_cachedRankedWords;
    });

    if (!rankedWords || rankedWords.count == 0) return @{};

    // Filter by prefix and assign rank-based scores (higher rank = higher score)
    NSString *lowerPrefix = prefix.lowercaseString;
    NSMutableDictionary<NSString *, NSNumber *> *matching = [NSMutableDictionary dictionary];
    float totalCount = (float)rankedWords.count;

    for (NSInteger i = 0; i < (NSInteger)rankedWords.count; i++) {
        NSString *word = rankedWords[i];
        if ([word hasPrefix:lowerPrefix]) {
            // Rank 0 (best) gets highest score, last gets lowest
            matching[word] = @(totalCount - (float)i);
        }
    }

    return [matching copy];
}

@end
