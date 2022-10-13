using DoubleArrayTries
using Documenter

DocMeta.setdocmeta!(DoubleArrayTries, :DocTestSetup, :(using DoubleArrayTries); recursive=true)

makedocs(;
    modules=[DoubleArrayTries],
    authors="chengchingwen <adgjl5645@hotmail.com> and contributors",
    repo="https://github.com/chengchingwen/DoubleArrayTries.jl/blob/{commit}{path}#{line}",
    sitename="DoubleArrayTries.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://chengchingwen.github.io/DoubleArrayTries.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/chengchingwen/DoubleArrayTries.jl",
    devbranch="main",
)
