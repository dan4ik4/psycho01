import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import current_active_user
from app.crud.patient_assignment import (
    get_active_assignments,
    get_finished_assignments,
    get_incoming_assignment_requests,
    get_latest_patient_assignment,
)
from app.db.deps import get_db
from app.models.user import User
from app.schemas.patient_assignment import (
    PatientAssignmentFinish,
    PatientAssignmentOut,
    PatientAssignmentReject,
    PatientAssignmentRequestCreate,
    PatientAssignmentWithLatestEventOut,
)
from app.services.patient_assignment import (
    accept_assignment,
    cancel_assignment,
    finish_assignment,
    reject_assignment,
    request_assignment,
)
from app.services.presentation import assignment_views

router = APIRouter(
    prefix="/patient-assignments",
    tags=["Patient assignments"],
)


@router.post(
    "/request",
    response_model=PatientAssignmentOut,
    status_code=status.HTTP_201_CREATED,
)
async def request_assignment_endpoint(
    data: PatientAssignmentRequestCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    if user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Psychologist cannot request assignment",
        )

    return await request_assignment(
        db=db,
        patient_id=user.id,
        psychologist_id=data.psychologist_id,
        comment=data.comment,
    )


@router.post(
    "/{assignment_id}/accept",
    response_model=PatientAssignmentOut,
)
async def accept_assignment_endpoint(
    assignment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await accept_assignment(
        db=db,
        assignment_id=assignment_id,
        psychologist_id=user.id,
    )


@router.post(
    "/{assignment_id}/reject",
    response_model=PatientAssignmentOut,
)
async def reject_assignment_endpoint(
    assignment_id: uuid.UUID,
    data: PatientAssignmentReject,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await reject_assignment(
        db=db,
        assignment_id=assignment_id,
        psychologist_id=user.id,
        comment=data.comment,
    )


@router.post(
    "/{assignment_id}/finish",
    response_model=PatientAssignmentOut,
)
async def finish_assignment_endpoint(
    assignment_id: uuid.UUID,
    data: PatientAssignmentFinish,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await finish_assignment(
        db=db,
        assignment_id=assignment_id,
        performed_by_id=user.id,
        comment=data.comment,
    )


@router.post(
    "/{assignment_id}/cancel",
    response_model=PatientAssignmentOut,
)
async def cancel_assignment_endpoint(
    assignment_id: uuid.UUID,
    data: PatientAssignmentFinish,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    return await cancel_assignment(
        db=db,
        assignment_id=assignment_id,
        patient_id=user.id,
        comment=data.comment,
    )


# get


@router.get(
    "/my",
    response_model=PatientAssignmentWithLatestEventOut | None,
)
async def get_my_assignment_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    if user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can access this endpoint",
        )

    assignment_data = await get_latest_patient_assignment(
        db=db,
        patient_id=user.id,
    )

    if assignment_data is None:
        return None

    assignment, latest_event = assignment_data

    return (await assignment_views(db, [(assignment, latest_event)]))[0]


@router.get(
    "/incoming",
    response_model=list[PatientAssignmentWithLatestEventOut],
)
async def get_incoming_assignments_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    if not user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can access incoming assignments",
        )

    assignments = await get_incoming_assignment_requests(
        db=db,
        psychologist_id=user.id,
    )

    return await assignment_views(db, assignments)


@router.get(
    "/active",
    response_model=list[PatientAssignmentWithLatestEventOut],
)
async def get_active_assignments_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    if not user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can access active assignments",
        )

    assignments = await get_active_assignments(
        db=db,
        psychologist_id=user.id,
    )

    return await assignment_views(db, assignments)


@router.get(
    "/finished",
    response_model=list[PatientAssignmentWithLatestEventOut],
)
async def get_finished_assignments_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    assignments = await get_finished_assignments(
        db=db,
        user_id=user.id,
    )

    return await assignment_views(db, assignments)
