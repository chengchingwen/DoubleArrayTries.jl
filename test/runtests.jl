using DoubleArrayTries
using Test
using Random

const DAT = DoubleArrayTries

@testset "DoubleArrayTries.jl" begin
    @testset "pdep" begin
        for _ in 1:100000
            x64 = rand(UInt64)
            y64 = rand(UInt64)
            x32 = rand(UInt32)
            y32=  rand(UInt32)
            @test DAT.pdep(x64, y64) == DAT._pdep(x64, y64)
            @test DAT.pdep(x32, y32) == DAT._pdep(x32, y32)
        end
    end
    @testset "bcvector" begin
        num_units = 20000
        for max_size in (UInt64(10000), typemax(UInt64))
            bc_units = rand(1:(max_size - 1), 2 * num_units)
            leaves = rand(num_units) .< 0.2
            bc = DAT.BCVector(bc_units, leaves)
            @test DAT.num_units(bc) == num_units
            @test DAT.num_leaves(bc) == sum(leaves)
            for i = 1:num_units
                @test DAT.isleaf(bc, i) == leaves[i]
                if leaves[i]
                    @test DAT.LINK₀(bc, i - 1) == bc_units[DAT.BASE₁(i)]
                else
                    @test DAT.BASE₀(bc, i - 1) == bc_units[DAT.BASE₁(i)]
                end
                @test DAT.CHECK₀(bc, i - 1) == bc_units[DAT.CHECK₁(i)]
            end
        end
    end

    @testset "tvector" begin
        num_tails = 20000
        for _sufs in (
            ["ML", "STATS", "A", "M", "L", "AKDD", "M", "R", "DD", "OD"],
            (randstring('A':'B', rand(1:60)) for i = 1:num_tails),
            (randstring('A':'Z', rand(1:60)) for i = 1:num_tails),
            (randstring(Char(0):Char(255), rand(1:60)) for i = 1:num_tails),
        )
            sufs = collect(_sufs)
            for bin_mode in (true, false)
                bin_mode || all(key->all(!iszero, codeunits(key)), sufs) || continue
                m_suffixes = DAT.based₀(@NamedTuple{str::AbstractVector{UInt8}, npos::UInt64}[])
                ids = Vector{UInt64}(undef, length(sufs))
                for i = 1:length(sufs)
                    DAT.set_suffix!(m_suffixes, codeunits(sufs[i]), i - 1)
                end
                m_chars, m_terms = DAT.based₁.(DAT.complete!(m_suffixes, ids, bin_mode,
                                                             (m_units, npos, tpos)-> m_units[npos + 1] = tpos))
                tvec = DAT.TVector(m_chars, m_terms)
                for (id₀, suf) in zip(ids, sufs)
                    id = id₀ + 1
                    @test DAT.match(tvec, suf, id)
                    @test String(collect(DAT.decode(tvec, id))) == suf
                end
            end
        end
    end

    @testset "basic op" begin
        keys = [
            "AirPods",  "AirTag",  "Mac",  "MacBook", "MacBook_Air", "MacBook_Pro",
            "Mac_Mini", "Mac_Pro", "iMac", "iPad",    "iPhone",      "iPhone_SE",
        ]
        other = [
            "Google_Pixel", "iPad_mini", "iPadOS", "iPod", "ThinkPad",
        ]
        for bin_mode in (true, false)
            dat = DoubleArrayTrie(keys; bin_mode)
            @test dat.num_keys == length(keys)
            @test DAT.max_length(dat) == maximum(ncodeunits, keys)
            @inferred lookup(dat, "A")
            @inferred Nothing decode(dat, 5)
            @test lookup(dat, "A") == 0
            @test decode(dat, length(keys)+100) == nothing
            @test decode(dat, 0) == nothing
            @test decode(dat, -100) == nothing
            for key in keys
                id = lookup(dat, key)
                @test id in 1:dat.num_keys
                @test decode(dat, id) == key
            end
            for key in other
                @test lookup(dat, key) == 0
            end
            expected_prefixes = ["Mac", "MacBook", "MacBook_Pro"]
            for (i, prefix) in enumerate(CommonPrefixSearch(dat, "MacBook_Pro_13inch"))
                id, decoded = prefix
                @test expected_prefixes[i] == decoded
                @test lookup(dat, decoded) == id
                @test decode(dat, id) == decoded
            end
            expected_predictives = ["MacBook", "MacBook_Air", "MacBook_Pro"]
            for (i, predictive) in enumerate(PredictiveSearch(dat, "MacBook"))
                id, decoded = predictive
                @test expected_predictives[i] == decoded
                @test lookup(dat, decoded) == id
                @test decode(dat, id) == decoded
            end
            @test map(id->decode(dat, id), DAT.PredictiveIDSearch(dat, "MacBook")) == expected_predictives
            for (decoded, id) in dat
                @test decoded in keys
                @test lookup(dat, decoded) == id
                @test decode(dat, id) == decoded
            end
        end
    end

    @testset "real example" begin
        raw_keys = readlines(joinpath(@__DIR__, "keys.txt"))
        for _ in 1:3
            for bin_mode in (true, false)
                ids = shuffle(1:length(raw_keys))
                bound = div(length(raw_keys), 10)
                others = @view raw_keys[1:bound]
                keys = @view raw_keys[bound+1:end]
                dat = DoubleArrayTrie(keys; bin_mode)
                @test dat.num_keys == length(keys)
                @test DAT.max_length(dat) == maximum(ncodeunits, keys)
                for key in keys
                    id = lookup(dat, key)
                    @test id in 1:dat.num_keys
                    @test decode(dat, id) == key
                end
                for key in others
                    @test lookup(dat, key) == 0
                end
                queries = rand(raw_keys, div(length(raw_keys), 100))
                for query in queries
                    for (id, prefix) in CommonPrefixSearch(dat, query)
                        @test ncodeunits(query) >= ncodeunits(prefix)
                        @test @view(codeunits(query)[begin:ncodeunits(prefix)]) == codeunits(prefix)
                        @test id == lookup(dat, prefix)
                        @test prefix == decode(dat, id)
                    end
                    query_prefix = String(codeunits(query)[begin:(div(ncodeunits(query), 3) + 1)])
                    for (id, predictive) in PredictiveSearch(dat, query_prefix)
                        @test ncodeunits(query_prefix) <= ncodeunits(predictive)
                        @test @view(codeunits(predictive)[begin:ncodeunits(query_prefix)]) == codeunits(query_prefix)
                        @test id == lookup(dat, predictive)
                        @test predictive == decode(dat, id)
                    end
                end
                for (decoded, id) in dat
                    @test id == lookup(dat, decoded)
                    @test decoded == decode(dat, id)
                end
            end
        end
    end
end

function random_test(seed, domain, len_domain, n)
    if VERSION < v"1.8"
        rng = Random.MersenneTwister(seed)
    else
        rng = Random.Xoshiro(seed)
    end
    raw_keys = unique!([randstring(rng, domain, rand(rng, len_domain)) for i = 1:n])
    for bin_mode in (true, false)
        bin_mode || all(key->all(!iszero, codeunits(key)), raw_keys) || continue
        ids = shuffle(1:length(raw_keys))
        bound = div(length(raw_keys), 10)
        others = @view raw_keys[1:bound]
        keys = @view raw_keys[bound+1:end]
        dat = DoubleArrayTrie(keys; bin_mode)
        @test length(dat) == length(keys)
        @test DAT.max_length(dat) == maximum(ncodeunits, keys)
        for key in keys
            id = lookup(dat, key)
            @test id in 1:dat.num_keys
            @test decode(dat, id) == key
        end
        for key in others
            @test lookup(dat, key) == 0
        end
        queries = rand(rng, raw_keys, div(length(raw_keys), 100))
        for query in queries
            for (id, prefix) in CommonPrefixSearch(dat, query)
                @test ncodeunits(query) >= ncodeunits(prefix)
                @test @view(codeunits(query)[begin:ncodeunits(prefix)]) == codeunits(prefix)
                @test id == lookup(dat, prefix)
                @test prefix == decode(dat, id)
            end
            query_prefix = String(codeunits(query)[begin:(div(ncodeunits(query), 3) + 1)])
            for (id, predictive) in PredictiveSearch(dat, query_prefix)
                @test ncodeunits(query_prefix) <= ncodeunits(predictive)
                @test @view(codeunits(predictive)[begin:ncodeunits(query_prefix)]) == codeunits(query_prefix)
                @test id == lookup(dat, predictive)
                @test predictive == decode(dat, id)
            end
            @test map(first, PredictiveSearch(dat, query_prefix)) == DAT.predictive_id_search(dat, query_prefix)
        end
        for (decoded, id) in dat
            @test id == lookup(dat, decoded)
            @test decoded == decode(dat, id)
        end
    end
end

for (name, setting) in (
    "A-B 10K"        => ('A':'B', 1:60, 10000),
    "A-Z 10K"        => ('A':'Z', 1:60, 10000),
    "0x00-0xFF 10K"  => (Char(0):Char(255), 1:60, 10000),
    "A-B 100K"       => ('A':'B', 1:60, 100000),
    "A-Z 100K"       => ('A':'Z', 1:60, 100000),
    "0x00-0xFF 100K" => (Char(0):Char(255), 1:60, 100000),
    "A-B 200K"       => ('A':'B', 1:60, 200000),
)
    @testset "Large Random ($name)" begin
        domain, len_domain, n = setting
        for _ in 1:3
            seed = rand(UInt64)
            @info "Testing $name" seed
            random_test(seed, domain, len_domain, n)
        end
    end
end
