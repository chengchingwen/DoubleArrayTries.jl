struct PredictiveSearch{T <: AbstractVector{UInt8}}
    dat::DoubleArrayTrie
    key::T
end
PredictiveSearch(dat::DoubleArrayTrie, key::AbstractString) = PredictiveSearch(dat, codeunits(key))

Base.IteratorSize(::PredictiveSearch) = Base.SizeUnknown()

function Base.iterate(itr::PredictiveSearch)
    dat = itr.dat
    decoded = Vector{UInt8}(undef, itr.dat.table.max_length) |> empty!
    stack = @NamedTuple{label::UInt8, kpos::Int, npos::Int}[]
    npos = 1
    for kpos = 1:length(itr.key)
        if isleaf(dat.bcvec, npos)
            tpos = Int(LINK₀(npos) + 1)
            isone(tpos) && return nothing
            prefix_match(dat.tvec, @view(itr.key[kpos:end]), tpos) == 0 && return nothing
            id = npos_to_id(dat, npos)
            decode!(dat.tvec, decoded, tpos)
            return (id, String(StringView(decoded))), (; decoded, stack, isend = true)
        end

        c = itr.key[kpos]
        npos₀ = UInt64(npos - 1)
        cpos₀ = BASE₀(dat.bcvec, npos₀) ⊻ get_code(dat.table, c)
        CHECK₀(dat.bcvec, cpos₀) != npos₀ && return nothing
        npos = Int(cpos₀) + 1
        push!(decoded, c)
    end
    push!(stack, (; label = isempty(decoded) ? 0x0 : decoded[end], kpos = length(itr.key), npos))
    return iterate(itr, (; decoded, stack, isend = false))
end

function Base.iterate(itr::PredictiveSearch, state)
    state.isend && return nothing
    dat = itr.dat

    while !isempty(state.stack)
        (; label, kpos, npos) = pop!(state.stack)
        npos₀ = UInt64(npos - 1)
        if kpos > 0
            resize!(state.decoded, kpos)
            @inbounds state.decoded[end] = label
        end
        if isleaf(dat.bcvec, npos)
            id = npos_to_id(dat, npos)
            decode!(dat.tvec, state.decoded, Int(LINK₀(dat.bcvec, npos₀)) + 1)
            return (id, String(StringView(state.decoded))), state
        end

        base₀ = BASE₀(dat.bcvec, npos₀)
        for c in Iterators.reverse(dat.table.alphabet)
            cpos₀ = base₀ ⊻ get_code(dat.table, c)
            if CHECK₀(dat.bcvec, cpos₀) == npos₀
                push!(state.stack, (; label = c, kpos = kpos + 1, npos = Int(cpos₀) + 1))
            end
        end

        if dat.terms[npos]
            id = npos_to_id(dat, npos)
            return (id, String(StringView(state.decoded))), state
        end
    end

    return nothing
end

predictive_search(dat::DoubleArrayTrie, key) = collect(Tuple{Int, String}, PredictiveSearch(dat, key))

struct PredictiveIDSearch{T <: AbstractVector{UInt8}}
    dat::DoubleArrayTrie
    key::T
end
PredictiveIDSearch(dat::DoubleArrayTrie, key::AbstractString) = PredictiveIDSearch(dat, codeunits(key))

Base.IteratorSize(::PredictiveIDSearch) = Base.SizeUnknown()

function Base.iterate(itr::PredictiveIDSearch)
    dat = itr.dat
    stack = @NamedTuple{label::UInt8, kpos::Int, npos::Int}[]
    npos = 1
    label = 0x0
    for kpos = 1:length(itr.key)
        if isleaf(dat.bcvec, npos)
            tpos = Int(LINK₀(npos) + 1)
            isone(tpos) && return nothing
            prefix_match(dat.tvec, @view(itr.key[kpos:end]), tpos) == 0 && return nothing
            id = npos_to_id(dat, npos)
            return id, (; stack, isend = true)
        end

        c = itr.key[kpos]
        npos₀ = UInt64(npos - 1)
        cpos₀ = BASE₀(dat.bcvec, npos₀) ⊻ get_code(dat.table, c)
        CHECK₀(dat.bcvec, cpos₀) != npos₀ && return nothing
        npos = Int(cpos₀) + 1
        label = c
    end
    push!(stack, (; label, kpos = length(itr.key), npos))
    return iterate(itr, (; stack, isend = false))
end

function Base.iterate(itr::PredictiveIDSearch, state)
    state.isend && return nothing
    dat = itr.dat

    while !isempty(state.stack)
        (; label, kpos, npos) = pop!(state.stack)
        npos₀ = UInt64(npos - 1)
        if isleaf(dat.bcvec, npos)
            id = npos_to_id(dat, npos)
            return id, state
        end

        base₀ = BASE₀(dat.bcvec, npos₀)
        for c in Iterators.reverse(dat.table.alphabet)
            cpos₀ = base₀ ⊻ get_code(dat.table, c)
            if CHECK₀(dat.bcvec, cpos₀) == npos₀
                push!(state.stack, (; label = c, kpos = kpos + 1, npos = Int(cpos₀) + 1))
            end
        end

        if dat.terms[npos]
            id = npos_to_id(dat, npos)
            return id, state
        end
    end

    return nothing
end

predictive_id_search(dat::DoubleArrayTrie, key) = collect(Int, PredictiveIDSearch(dat, key))
