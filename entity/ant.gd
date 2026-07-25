class_name Ant
extends Node

#region Stats
const MAX_ENERGY: float = 100.0
const MAX_HEALTH: float = 100.0
const MAX_CARRY_MASS: float = 10.0

#region Senses
const REACH_RANGE: float = 10.0
const VISION_RANGE: float = 60.0
const OLFACTORY_RANGE: float = 200.0

#region Status
var energy: float = MAX_ENERGY
var health: float = MAX_HEALTH
var carry_mass: float = 0.0
