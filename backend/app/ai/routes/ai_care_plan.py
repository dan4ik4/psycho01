import uuid
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.schemas.ai_care_plan import (
    AiCarePlanCreate,
    AiCarePlanVersionCreate,
    AiCarePlanVersionRead,
    AiCarePlanActivate,
    AiCarePlanStateChange,
    AiCarePlanEventRead,
    AiCarePlanPsychologistRead,
    AiCarePlanPatientRead,
)
from app.ai.services.ai_care_plan import (
    create_care_plan,
    create_new_care_plan_version,
    activate_care_plan_version,
    pause_care_plan,
    complete_care_plan,
    get_psychologist_care_plan,
    get_patient_care_plan,
)
from app.auth.deps import current_active_user
from app.db.deps import get_db
from app.models.user import User


router = APIRouter(
    prefix="/care-plans",
    tags=["AI care plans"],
)


@router.post(
    "",
    response_model=AiCarePlanPsychologistRead,
    status_code=status.HTTP_201_CREATED,
)
async def create_care_plan_endpoint(
    data: AiCarePlanCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiCarePlanPsychologistRead:
    if not user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can create care plans",
        )

    care_plan, version = await create_care_plan(
        db=db,
        assignment_id=data.assignment_id,
        psychologist_id=user.id,
        instructions_for_ai=data.instructions_for_ai,
        patient_recommendations=data.patient_recommendations,
    )

    return AiCarePlanPsychologistRead(
        care_plan=care_plan,
        latest_version=version,
        latest_event=None,
    )
    
@router.post(
    "/{assignment_id}/versions",
    response_model=AiCarePlanVersionRead,
    status_code=status.HTTP_201_CREATED,
)
async def create_care_plan_version_endpoint(
    assignment_id: uuid.UUID,
    data: AiCarePlanVersionCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiCarePlanVersionRead:
    if not user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can create care plan versions",
        )

    return await create_new_care_plan_version(
        db=db,
        assignment_id=assignment_id,
        psychologist_id=user.id,
        instructions_for_ai=data.instructions_for_ai,
        patient_recommendations=data.patient_recommendations,
    )
    
@router.post(
    "/{assignment_id}/activate",
    response_model=AiCarePlanEventRead,
)
async def activate_care_plan_version_endpoint(
    assignment_id: uuid.UUID,
    data: AiCarePlanActivate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiCarePlanEventRead:
    if not user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can activate care plans",
        )

    return await activate_care_plan_version(
        db=db,
        assignment_id=assignment_id,
        psychologist_id=user.id,
        version_id=data.version_id,
        comment=data.comment,
    )
    
@router.post(
    "/{assignment_id}/pause",
    response_model=AiCarePlanEventRead,
)
async def pause_care_plan_endpoint(
    assignment_id: uuid.UUID,
    data: AiCarePlanStateChange,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiCarePlanEventRead:
    if not user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can pause care plans",
        )

    return await pause_care_plan(
        db=db,
        assignment_id=assignment_id,
        psychologist_id=user.id,
        comment=data.comment,
    )
    
@router.post(
    "/{assignment_id}/complete",
    response_model=AiCarePlanEventRead,
)
async def complete_care_plan_endpoint(
    assignment_id: uuid.UUID,
    data: AiCarePlanStateChange,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiCarePlanEventRead:
    if not user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can complete care plans",
        )

    return await complete_care_plan(
        db=db,
        assignment_id=assignment_id,
        psychologist_id=user.id,
        comment=data.comment,
    )
    
@router.get(
    "/{assignment_id}/psychologist",
    response_model=AiCarePlanPsychologistRead,
)
async def get_psychologist_care_plan_endpoint(
    assignment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiCarePlanPsychologistRead:
    if not user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only psychologists can access this care plan",
        )

    care_plan, latest_version, latest_event = (
        await get_psychologist_care_plan(
            db=db,
            assignment_id=assignment_id,
            psychologist_id=user.id,
        )
    )

    return AiCarePlanPsychologistRead(
        care_plan=care_plan,
        latest_version=latest_version,
        latest_event=latest_event,
    )
    
@router.get(
    "/{assignment_id}/patient",
    response_model=AiCarePlanPatientRead,
)
async def get_patient_care_plan_endpoint(
    assignment_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(current_active_user),
) -> AiCarePlanPatientRead:
    if user.is_psychologist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can access this care plan",
        )

    care_plan, version, latest_event = await get_patient_care_plan(
        db=db,
        assignment_id=assignment_id,
        patient_id=user.id,
    )

    return AiCarePlanPatientRead(
        care_plan_id=care_plan.id,
        version_id=version.id,
        patient_recommendations=version.patient_recommendations,
        event_type=latest_event.event_type,
    )
    
