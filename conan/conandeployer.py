import shutil
from pathlib import Path


def deploy(graph, output_folder: str, **kwargs):
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

    if "odrcore" in deps:
        dep = deps["odrcore"]
        conanfile.output.info(f"Deploying odrcore to {output_folder}")
        shutil.copytree(
            f"{dep.package_folder}/share",
            f"{output_folder}/odrcore",
            **copytree_kwargs,
        )

    if "pdf2htmlex" in deps:
        dep = deps["pdf2htmlex"]
        conanfile.output.info(f"Deploying pdf2htmlex to {output_folder}")
        shutil.copytree(
            f"{dep.package_folder}/share/pdf2htmlEX",
            f"{output_folder}/pdf2htmlex",
            **copytree_kwargs,
        )

    if "poppler-data" in deps:
        dep = deps["poppler-data"]
        conanfile.output.info(f"Deploying poppler-data to {output_folder}")
        shutil.copytree(
            f"{dep.package_folder}/share/poppler",
            f"{output_folder}/poppler",
            **copytree_kwargs,
        )

    if "fontconfig" in deps:
        dep = deps["fontconfig"]
        conanfile.output.info(f"Deploying fontconfig to {output_folder}")
        shutil.copytree(
            f"{dep.package_folder}/res/share",
            f"{output_folder}/fontconfig",
            **copytree_kwargs,
        )

    with (
        open(f"{output_folder}/input-files.xcfilelist", "w") as f_in,
        open(f"{output_folder}/output-files.xcfilelist", "w") as f_out,
    ):
        for file in Path(output_folder).glob("**/*"):
            file = file.relative_to(output_folder)
            if file.suffix == ".xcfilelist":
                continue
            f_in.write(f"$(PROJECT_DIR)/{output_folder.name}/{file}\n")
            f_out.write(
                f"${{TARGET_BUILD_DIR}}/${{UNLOCALIZED_RESOURCES_FOLDER_PATH}}/{file}\n"
            )
