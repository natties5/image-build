#!/usr/bin/env python3
"""
State - Central menu state management
"""

from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parent.parent


class CenterState:
    """Manages the state for the central menu."""
    
    def __init__(self):
        self.active_domain: Optional[str] = None
        self.last_command: Optional[str] = None
    
    def set_active_domain(self, domain: str) -> None:
        """Set the currently active domain."""
        self.active_domain = domain
    
    def get_active_domain(self) -> Optional[str]:
        """Get the currently active domain."""
        return self.active_domain
    
    def clear_active_domain(self) -> None:
        """Clear the active domain."""
        self.active_domain = None
    
    def record_command(self, command: str) -> None:
        """Record the last executed command."""
        self.last_command = command
    
    def get_last_command(self) -> Optional[str]:
        """Get the last executed command."""
        return self.last_command
