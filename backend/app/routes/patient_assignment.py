from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
import uuid

from app.db.deps import get_db
from app.auth.deps import current_active_user
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
    request_assignment,
    reject_assignment,
    finish_assignment,
    cancel_assignment,
)
from app.crud.patient_assignment import (
    get_assignments_with_latest_events,
    get_latest_patient_assignment,
    get_incoming_assignment_requests,
    get_active_assignments,
    get_finished_assignments,

)

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
    
    try:
        assignment = await request_assignment(
            db=db,
            patient_id=user.id,
            psychologist_id=data.psychologist_id,
            comment=data.comment,
        )

        return assignment

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
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
    try:
        assignment = await accept_assignment(
            db=db,
            assignment_id=assignment_id,
            psychologist_id=user.id,
        )

        return assignment

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
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
    try:
        assignment = await reject_assignment(
            db=db,
            assignment_id=assignment_id,
            psychologist_id=user.id,
            comment=data.comment,
        )

        return assignment

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
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
    try:
        assignment = await finish_assignment(
            db=db,
            assignment_id=assignment_id,
            performed_by_id=user.id,
            comment=data.comment,
        )

        return assignment

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
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
    try:
        assignment = await cancel_assignment(
            db=db,
            assignment_id=assignment_id,
            patient_id=user.id,
            comment=data.comment,
        )

        return assignment

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    
#get

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
            detail="Psychologist cannot request assignment",
        )
       
    assignment = await get_latest_patient_assignment(
        db=db,
        patient_id=user.id,
    )

    if assignment is None:
        return None

    result = await get_assignments_with_latest_events(
        db=db,
        assignments=[assignment],
    )

    return result[0]

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
            detail="Patient cannot view incoming assignments",
        )
    assignments = await get_incoming_assignment_requests(
        db=db,
        psychologist_id=user.id,
    )

    return await get_assignments_with_latest_events(
        db=db,
        assignments=assignments,
    )

@router.get(
    "/active",
    response_model=list[PatientAssignmentWithLatestEventOut],
)
async def get_active_assignments_endpoint(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
):
    assignments = await get_active_assignments(
        db=db,
        user_id=user.id,
    )

    return await get_assignments_with_latest_events(
        db=db,
        assignments=assignments,
    )

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

    return await get_assignments_with_latest_events(
        db=db,
        assignments=assignments,
    )