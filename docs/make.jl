using StatusWindows
using Documenter

DocMeta.setdocmeta!(StatusWindows, :DocTestSetup, :(using StatusWindows); recursive=true)

makedocs(;
    modules=[StatusWindows],
    authors="Joris Pinkse <pinkse@gmail.com> and contributors",
    sitename="StatusWindows.jl",
    format=Documenter.HTML(;
        canonical="https://NittanyLion.github.io/StatusWindows.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/NittanyLion/StatusWindows.jl",
    devbranch="main",
)
