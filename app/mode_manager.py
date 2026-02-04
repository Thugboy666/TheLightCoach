from pathlib import Path
from typing import Dict

from app.data_manager import DataManager


class ModeManager:
    def __init__(self, data_root: Path) -> None:
        self.data_root = data_root
        self._cache: Dict[str, DataManager] = {}

    def get_mode(self, mode: str) -> DataManager:
        if mode not in self._cache:
            self._cache[mode] = DataManager(self.data_root, mode)
        return self._cache[mode]
