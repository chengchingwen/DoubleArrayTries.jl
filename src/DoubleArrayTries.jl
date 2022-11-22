module DoubleArrayTries

using StringViews
using OffsetArrays

export DoubleArrayTrie, lookup, decode,
    common_prefix_search, CommonPrefixSearch, predictive_search, PredictiveSearch

include("build.jl")
include("succinct.jl")
include("bvector.jl")
include("cvector.jl")
include("tvector.jl")
include("bcvector15.jl")
include("codetable.jl")
include("trie.jl")
include("prefix.jl")
include("predictive.jl")
include("dict.jl")

end
