# Samera 2026-07-14: overlay do triplet builtin x86-windows-static.
# Motivo: o vcpkg pinado escolhia sozinho o toolset v142 -> generator "Visual Studio 16 2019".
# O runner windows-2019 foi APOSENTADO pelo GitHub e o windows-2022 so tem VS 2022 (v143),
# entao o openal-soft (unico port que usa o generator do VS em vez de Ninja) morria com
# "could not find any instance of Visual Studio". Este vcpkg JA mapeia v143 -> "Visual Studio 17 2022"
# (scripts/cmake/vcpkg_configure_cmake.cmake), entao basta fixar o toolset.
set(VCPKG_TARGET_ARCHITECTURE x86)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_PLATFORM_TOOLSET v143)
