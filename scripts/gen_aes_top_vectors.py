"""Gera os vetores do testbench do minisoc_aes_top a partir de aes_ref.py.

Para cada caso (modo x sentido x número de blocos), grava a configuração e
as imagens completas da memória (1024 palavras) antes e depois da operação.
As palavras fora da região processada devem ficar inalteradas.

Uso: python3 scripts/gen_aes_top_vectors.py [diretório de saída]
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import aes_ref  # noqa: E402

SEED = 2026
MEM_WORDS = 1024
MODES = [("ECB", aes_ref.MODE_ECB), ("CBC", aes_ref.MODE_CBC), ("CTR", aes_ref.MODE_CTR)]
NUM_BLOCKS = [1, 2, 256]


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "tb", "vectors")
    os.makedirs(out_dir, exist_ok=True)
    rng = random.Random(SEED)

    cfg_lines, in_lines, out_lines, names = [], [], [], []
    for name, mode in MODES:
        for decrypt in (0, 1):
            for n in NUM_BLOCKS:
                key = rng.getrandbits(128)
                iv = rng.getrandbits(128)
                # CTR com 256 blocos: o contador de 64 bits dá a volta
                counter = (1 << 64) - 3 if (mode == aes_ref.MODE_CTR and n == 256) else rng.getrandbits(64)
                mem = [rng.getrandbits(32) for _ in range(MEM_WORDS)]

                blocks = [(mem[4 * i] << 96) | (mem[4 * i + 1] << 64) | (mem[4 * i + 2] << 32) | mem[4 * i + 3]
                          for i in range(n)]
                res = aes_ref.run_mode(mode, decrypt, key, iv, counter, blocks)
                exp = list(mem)
                for i, b in enumerate(res):
                    for w in range(4):
                        exp[4 * i + w] = (b >> (96 - 32 * w)) & 0xFFFFFFFF

                # configuração: 6 entradas de 128 bits por caso
                for v in (mode, decrypt, n, key, iv, counter):
                    cfg_lines.append(f"{v:032x}")
                in_lines += [f"{w:08x}" for w in mem]
                out_lines += [f"{w:08x}" for w in exp]
                names.append(f"{name} {'decifra' if decrypt else 'cifra'} {n} bloco(s)")

    with open(os.path.join(out_dir, "aes_top_cfg.hex"), "w") as f:
        f.write("\n".join(cfg_lines) + "\n")
    with open(os.path.join(out_dir, "aes_top_mem_in.hex"), "w") as f:
        f.write("\n".join(in_lines) + "\n")
    with open(os.path.join(out_dir, "aes_top_mem_out.hex"), "w") as f:
        f.write("\n".join(out_lines) + "\n")
    with open(os.path.join(out_dir, "aes_top_cases.txt"), "w") as f:
        f.write("\n".join(f"{i:2d}: {s}" for i, s in enumerate(names)) + "\n")
    print(f"{len(names)} casos gravados em {os.path.normpath(out_dir)}")


if __name__ == "__main__":
    main()
