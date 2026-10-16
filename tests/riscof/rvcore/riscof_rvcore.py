"""RISCOF DUT plugin for the rv_core pipelined RV32I core."""
import logging
import os

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()


class rvcore(pluginTemplate):
    __model__ = "rvcore"
    __version__ = "0.1.0"

    def __init__(self, *args, **kwargs):
        sclass = super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            raise SystemExit("rvcore: missing plugin configuration")
        self.num_jobs = str(config.get("jobs", 1))
        self.pluginpath = os.path.abspath(config["pluginpath"])
        self.isa_spec = os.path.abspath(config["ispec"])
        self.platform_spec = os.path.abspath(config["pspec"])
        self.cross = config.get("cross", "riscv64-unknown-elf-")
        self.target_run = config.get("target_run", "1") != "0"
        self.runner = os.path.join(self.pluginpath, "run_test.sh")
        return sclass

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite
        self.compile_cmd = (
            self.cross + "gcc -march={0} -mabi=ilp32 -static -mcmodel=medany "
            "-fvisibility=hidden -nostdlib -nostartfiles -g "
            "-T " + self.pluginpath + "/env/link.ld "
            "-I " + self.pluginpath + "/env/ "
            "-I " + archtest_env + " {1} -o {2} {3}"
        )

    def build(self, isa_yaml, platform_yaml):
        ispec = utils.load_yaml(isa_yaml)["hart0"]
        self.xlen = "64" if 64 in ispec["supported_xlen"] else "32"

    def runTests(self, testList):
        makefile = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(makefile):
            os.remove(makefile)
        make = utils.makeUtil(makefilePath=makefile)
        make.makeCommand = "make -k -j" + self.num_jobs

        for testname in testList:
            entry = testList[testname]
            test = entry["test_path"]
            test_dir = entry["work_dir"]
            elf = "my.elf"
            sig_file = os.path.join(test_dir, self.name[:-1] + ".signature")

            march = entry["isa"].lower()
            for ext in ("zicsr", "zifencei"):
                if ext not in march:
                    march += "_" + ext
            macros = " -D" + " -D".join(entry["macros"])
            cmd = self.compile_cmd.format(march, test, elf, macros)

            simcmd = f"{self.runner} {elf} {sig_file}" if self.target_run else 'echo "NO RUN"'
            make.add_target(f"@cd {test_dir}; {cmd}; {simcmd};")

        make.execute_all(self.work_dir)
        if not self.target_run:
            raise SystemExit(0)
