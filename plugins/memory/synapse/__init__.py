"""Synapse memory plugin — MemoryProvider backed by Synapse Layer.

Provides persistent cross-session memory with PII sanitization, intent
classification, trust scoring, and SQLite-backed storage.

The Synapse Layer runs as a lightweight sidecar — no changes to the built-in
memory system. Context is injected via prefetch() and facts are stored via
sync_turn().

Config: memory.provider = "synapse" in ~/.hermes/config.yaml
Requires: pip install synapse-layer
"""

from __future__ import annotations

import json
import logging
import os
import sys
from typing import Any, Dict, List, Optional

from agent.memory_provider import MemoryProvider

logger = logging.getLogger(__name__)

# Add synapse_layer to path
_SITE_PKG = os.path.expanduser("~/.local/lib/python3.12/site-packages")
if _SITE_PKG not in sys.path:
    sys.path.insert(0, _SITE_PKG)


def _check_synapse_available() -> bool:
    """Check if synapse_memory is importable."""
    try:
        import importlib.util
        return importlib.util.find_spec("synapse_memory") is not None
    except Exception:
        return False


class SynapseMemoryProvider(MemoryProvider):
    """MemoryProvider backed by Synapse Layer."""

    @property
    def name(self) -> str:
        return "synapse"

    def __init__(self):
        self._memory = None
        self._session_id = None

    def is_available(self) -> bool:
        return _check_synapse_available()

    def initialize(self, session_id: str, **kwargs) -> None:
        from synapse_memory import SynapseMemory, SqliteBackend

        hermes_home = kwargs.get("hermes_home", os.path.expanduser("~/.hermes"))
        db_dir = os.path.join(hermes_home, "synapse")
        os.makedirs(db_dir, exist_ok=True)
        db_path = os.path.join(db_dir, "synapse.db")

        agent_id = kwargs.get("agent_identity", "hermes-agent")
        self._memory = SynapseMemory(
            agent_id=agent_id,
            backend=SqliteBackend(path=db_path),
        )
        self._session_id = session_id
        logger.info("SynapseProvider initialized: session=%s, db=%s", session_id, db_path)

    def system_prompt_block(self) -> str:
        if not self._memory:
            return ""
        return (
            "\n[Synapse Memory]: Persistent cross-session memory is active. "
            "Relevant context from past sessions will be injected before each turn."
        )

    def prefetch(self, query: str, *, session_id: str = "") -> str:
        """Recall relevant memories for this turn."""
        if not self._memory or not query:
            return ""
        try:
            import asyncio
            results = asyncio.run(self._memory.recall(query, top_k=5))
            if not results:
                return ""

            lines = []
            for r in results:
                if r.trust_quotient < 0.2:
                    continue
                lines.append(f"- {r.content} [trust:{r.trust_quotient:.2f}]")

            if not lines:
                return ""

            return (
                "\n\n<memory-context>\n"
                "[Synapse — recalled from past sessions]:\n"
                + "\n".join(lines)
                + "\n</memory-context>"
            )
        except Exception as e:
            logger.debug("Synapse prefetch failed: %s", e)
            return ""

    def sync_turn(self, user_content: str, assistant_content: str, *, session_id: str = "") -> None:
        """Store key facts from this turn in Synapse."""
        if not self._memory:
            return
        try:
            import asyncio
            # Store assistant response as potential memory (user messages are often transient)
            if assistant_content and len(assistant_content) > 20:
                # Extract only substantial content (skip short acknowledgements)
                asyncio.run(self._memory.store(
                    content=assistant_content[:800],
                    confidence=0.7,
                    metadata={"source": "turn", "session": session_id or self._session_id},
                ))
        except Exception as e:
            logger.debug("Synapse sync_turn failed: %s", e)

    def get_tool_schemas(self) -> List[Dict[str, Any]]:
        """No extra tools — Synapse works as context-only provider."""
        return []

    def on_memory_write(self, action: str, target: str, content: str) -> None:
        """Mirror built-in memory writes into Synapse.

        Called every time the agent uses the memory tool (add/replace/remove).
        This is the primary automatic ingestion path — the agent decides what's
        important, and Synapse captures it with sanitization + trust scoring.
        """
        if not self._memory or action == "remove":
            return
        try:
            import asyncio
            asyncio.run(self._memory.store(
                content=content,
                confidence=0.9,
                metadata={"source": "memory_tool", "action": action, "target": target},
            ))
            logger.info("Synapse mirrored memory write: %s/%s (%d chars)", action, target, len(content))
        except Exception as e:
            logger.debug("Synapse on_memory_write failed: %s", e)

    def sync_turn(self, user_content: str, assistant_content: str, *, session_id: str = "") -> None:
        """Store key facts from this turn in Synapse."""
        if not self._memory:
            return
        try:
            import asyncio
            # Store assistant response as potential memory
            if assistant_content and len(assistant_content) > 20:
                asyncio.run(self._memory.store(
                    content=assistant_content[:800],
                    confidence=0.7,
                    metadata={"source": "turn", "session": session_id or self._session_id},
                ))
        except Exception as e:
            logger.debug("Synapse sync_turn failed: %s", e)

    def on_session_end(self, messages: List[Dict[str, Any]]) -> None:
        """Extract and store key facts from the session."""
        if not self._memory or not messages:
            return
        try:
            import asyncio
            last_assistant = ""
            last_user = ""
            for msg in reversed(messages):
                role = msg.get("role", "")
                content = msg.get("content", "")
                if role == "assistant" and not last_assistant and content:
                    last_assistant = content[:800]
                elif role == "user" and not last_user and content:
                    last_user = content[:300]
                if last_assistant and last_user:
                    break
            if last_assistant:
                asyncio.run(self._memory.store(
                    content=f"Session: User said '{last_user[:100]}' → {last_assistant[:400]}",
                    confidence=0.75,
                    metadata={"source": "session_end", "session": self._session_id},
                ))
            logger.info("SynapseProvider: session end, facts stored")
        except Exception as e:
            logger.debug("SynapseProvider on_session_end failed: %s", e)

    def shutdown(self) -> None:
        self._memory = None


def register_memory_provider():
    """Plugin registration entry point."""
    return SynapseMemoryProvider()
