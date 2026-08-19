@tool
class_name BakedPropData
extends Resource

## Container fuer alle gebakten Modell-Gruppen eines Bakers.
## Wird als .tres gespeichert und vom BakedPropRuntime geladen.

@export var groups: Array[BakedPropGroup] = []
