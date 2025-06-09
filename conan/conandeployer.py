import shutil
from pathlib import Path


def deploy(graph, output_folder: str, **kwargs):
    project_folder = Path(__file__).parent.parent
    output_folder = Path(output_folder).resolve()

    conanfile = graph.root.conanfile
    conanfile.output.info(f"Custom deployer to {output_folder}")

    symlinks = conanfile.conf.get(
        "tools.deployer:symlinks", check_type=bool, default=True
    )
    arch = conanfile.settings.get_safe("arch")

    conanfile.output.info(f"Symlinks: {symlinks}")
    conanfile.output.info(f"Arch: {arch}")

    deps = {dep.ref.name: dep for dep in conanfile.dependencies.values()}

    print(f"Dependencies: {list(deps.keys())}")

    copytree_kwargs = {"symlinks": symlinks, "dirs_exist_ok": True}

    conan_files = output_folder / "files"

    if "odrcore" in deps:
        dep = deps["odrcore"]
        conanfile.output.info(f"Deploying odrcore to {conan_files}")
        shutil.copytree(
            f"{dep.package_folder}/share",
            f"{conan_files}/odrcore",
            **copytree_kwargs,
        )

    if "pdf2htmlex" in deps:
        dep = deps["pdf2htmlex"]
        conanfile.output.info(f"Deploying pdf2htmlex to {conan_files}")
        shutil.copytree(
            f"{dep.package_folder}/share/pdf2htmlEX",
            f"{conan_files}/pdf2htmlex",
            **copytree_kwargs,
        )

    if "poppler-data" in deps:
        dep = deps["poppler-data"]
        conanfile.output.info(f"Deploying poppler-data to {conan_files}")
        shutil.copytree(
            f"{dep.package_folder}/share/poppler",
            f"{conan_files}/poppler",
            **copytree_kwargs,
        )

    if "fontconfig" in deps:
        dep = deps["fontconfig"]
        conanfile.output.info(f"Deploying fontconfig to {conan_files}")
        shutil.copytree(
            f"{dep.package_folder}/res/share",
            f"{conan_files}/fontconfig",
            **copytree_kwargs,
        )

    with (
        open(f"{output_folder}/input-files.xcfilelist", "w") as f_in,
        open(f"{output_folder}/output-files.xcfilelist", "w") as f_out,
    ):
        for file in Path(conan_files).glob("**/*"):
            file = file.relative_to(conan_files)
            if file.suffix == ".xcfilelist":
                continue
            f_in.write(f"$(PROJECT_DIR)/{conan_files.relative_to(project_folder)}/{file}\n")
            f_out.write(
                f"${{TARGET_BUILD_DIR}}/${{UNLOCALIZED_RESOURCES_FOLDER_PATH}}/{file}\n"
            )
