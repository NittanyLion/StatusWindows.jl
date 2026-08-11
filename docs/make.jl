using Conkyish
using Documenter

DocMeta.setdocmeta!(Conkyish, :DocTestSetup, :(using Conkyish); recursive=true)

makedocs(;
    modules=[Conkyish],
    authors="Joris Pinkse <pinkse@gmail.com> and contributors",
    sitename="Conkyish.jl",
    format=Documenter.HTML(;
        canonical="https://NittanyLion.github.io/Conkyish.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/NittanyLion/Conkyish.jl",
    devbranch="main",
)
