using StatusWindows
using Documenter

DocMeta.setdocmeta!(StatusWindows, :DocTestSetup, :(using StatusWindows); recursive=true)

makedocs(;
    modules=[StatusWindows],
    # src/glfw/ is the package's binding to the GLFW C library. Its
    # docstrings are for whoever maintains it, not for anyone using a panel,
    # so they are documented in place and left out of the manual.
    checkdocs_ignored_modules=[StatusWindows.GLFW],
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
