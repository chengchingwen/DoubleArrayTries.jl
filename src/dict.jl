struct StringDict{V} <: AbstractDict{String, V}
    trie::DoubleArrayTrie
    indices::CVector
    values::Vector{V}
end

function StringDict(list::AbstractVector{<:Pair{<:AbstractString, V}}) where V
    perm = sortperm(list; by = first)
    dict_keys = map(i->first(list[i]), perm)
    @assert allunique(dict_keys) "Rpeated key found: all key must be unique"
    dict_values = map(x->x[2], list)
    trie = DoubleArrayTrie(dict_keys)
    uids = map(Base.Fix1(lookup, trie), dict_keys)
    indices = Vector{Int}(undef, length(dict_values))
    for (uid, origin_id) in zip(uids, perm)
        indices[uid] = origin_id
    end
    return StringDict{V}(trie, CVector(indices), dict_values)
end

function Base.get(d::StringDict, k::AbstractString, v)
    uid = lookup(d.trie, k)
    uid == 0 && return v
    return @inbounds d.values[d.indices[uid]]
end

Base.length(d::StringDict) = length(d.values)
Base.iterate(d::StringDict) = _iterate(d, iterate(PredictiveSearch(d.trie, "")))
Base.iterate(d::StringDict, state) = _iterate(d, iterate(PredictiveSearch(d.trie, ""), state))

_iterate(d, ::Nothing) = nothing
function _iterate(d, states)
    id, key = states[1]
    state = states[2]
    val = @inbounds d.values[d.indices[id]]
    return key=>val, state
end
