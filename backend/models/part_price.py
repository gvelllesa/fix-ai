from pydantic import BaseModel
from typing import Optional


class PartPrice(BaseModel):
    part_name: str
    price: Optional[float] = None
    currency: str = "USD"
    store_name: str
    url: Optional[str] = None
    is_oem: bool = False
