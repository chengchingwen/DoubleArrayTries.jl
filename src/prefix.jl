struct CommonPrefixSearch{T <: AbstractVector{UInt8}}
    dat::DoubleArrayTrie
    key::T
end
CommonPrefixSearch(dat::DoubleArrayTrie, key::AbstractString) = CommonPrefixSearch(dat, codeunits(key))

Base.IteratorSize(::CommonPrefixSearch) = Base.SizeUnknown()

function Base.iterate(itr::CommonPrefixSearch)
    npos, kpos, isend = 1, 1, false
    return Base.iterate(itr, (npos, kpos, isend))
end

function Base.iterate(itr::CommonPrefixSearch, (npos, kpos, isend))
    isend && return nothing
    dat = itr.dat
    bin = bin_mode(dat)
    len = length(itr.key)

    bin && kpos == len + 1 && return nothing

    while !isleaf(dat.bcvec, npos)
        bin && kpos == len + 1 && return nothing
        npos₀ = UInt64(npos - 1)
        cpos₀ = BASE₀(dat.bcvec, npos₀) ⊻ get_code(dat.table, kpos == len + 1 ? 0x0 : itr.key[kpos])
        kpos += 1

        CHECK₀(dat.bcvec, cpos₀) != npos₀ && return nothing

        npos = Int(cpos₀ + 1)
        if !isleaf(dat.bcvec, npos) && dat.terms[npos]
            id = npos_to_id(dat, npos)
            key = @view itr.key[Base.Slice(Base.OneTo(kpos-1))]
            return (id, StringView(key)), (npos, kpos, isend)
        end
    end
    isend = true

    tpos = Int(LINK₀(dat.bcvec, npos - 1)) + 1
    matched = prefix_match(dat.tvec, @view(itr.key[kpos:end]), tpos)
    isnothing(matched) && return nothing

    kpos += matched
    id = npos_to_id(dat, npos)
    key = @view itr.key[Base.Slice(Base.OneTo(kpos-1))]
    return (id, StringView(key)), (npos, kpos, isend)
end

function common_prefix_search(dat::DoubleArrayTrie, key)
    bytes = codeunits(key)
    T = typeof(StringView(@view bytes[:]))
    collect(Tuple{Int, T}, CommonPrefixSearch(dat, key))
end
