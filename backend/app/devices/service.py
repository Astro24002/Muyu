"""Device-domain service exports.

High-risk enrollment is implemented by ``WorkspaceService`` so membership,
device, challenge, and cursor work stays in one transaction.  This module is
the stable feature boundary for callers that do not need the workspace API.
"""

from app.workspaces.service import ApprovalChallenge, WorkspaceConflict, WorkspaceService

__all__ = ["ApprovalChallenge", "WorkspaceConflict", "WorkspaceService"]
