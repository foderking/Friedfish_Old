##
## Implements functionality for move generation
##
## references
##  - [zephyr chess engine project report]()
##
import util
import bitops
import options

type
  ## `Move` Completey encodes all information of a move in a 32 bit number
  ## 00000000000000000000000000000000
  ## ~~~|~~~~~|~~~~~|~~~~~|~~~|~~|~|~ 
  ## |||29....23....17....11..7..4.2.
  ## ||30     |     |     |   |  | |          
  ## |31|     |     |     |   |  | +> (2 bits) which piece to promote to         : `PromotionField`
  ## 32||     |     |     |   |  +--> (2 bits) the castling status               : `CastlingField`
  ## ||||     |     |     |   +-----> (3 bits) the captured piece                : `CapturedPieceField`
  ## ||||     |     |     +---------> (4 bits) the piece making the move         : `MovingPieceField`
  ## ||||     |     +---------------> (6 bits) the location to move to in index  : `LocationToField`
  ## ||||     +---------------------> (6 bits) the location to move from in index: `LocationFromField`
  ## |||+---------------------------> (6 bits) the location of the pawn captured during enPassant: `enPassantCapture`
  ## ||+----------------------------> (1 bit ) indicates the move is a piece promotion : `isPromotionMove`
  ## |+-----------------------------> (1 bit ) indicates the move is en passant        : `isEnPassantMove`
  ## +------------------------------> (1 bit ) indicates the move is a null move
  Move* = int32

  ## Encodes all posible value in promotion field within two bits (only relevant is the piece is a pawn)
  ## Rook = 0, Bishop = 1 or 0b01, Knight = 2 or 0b10, Queen = 3 or 0b11
  ## Note: In implementation 1 is subtract from the ordinal..
  ## since the orignal mapping from `Pieces` is Pawn=0, Rook=1, Bishop=2.. and Pawn is not valid
  PromotionField* = enum
    Rook_Promotion,  Bishop_Promotion, Knight_Promotion, Queen_Promotion

  ## Encodes all possible values of castling field within two bits
  ## Only three possible options of no castling, queen and king side castling
  ## no castling = 00, queen side = 01, king side  = 2 or 0b10
  CastlingField*  = enum
    No_Castling, QueenSide_Castling, KingSide_Castling

  ## CapturedPieceField* = ValidPiece
  ## Encodes the all posible captured pieces (king excluded)
  ## the color is not relevant since its color is the opposite of the moving piece

  ## MovingPieceField* = ValidPiece
  ## Encodes all possible moving pieces within 4 bits
  ## Pawn=0b0000, Rook=0b0001, Bishop=0b0010, Knight=0b0011, Queen=0b0100, King=0b0101
  ## the leftmost bit determines if it is black or white

  ## LocationToField* =  BoardIndex
  ## Encodes the location to move to in little endian rank-file mapping
  ## all possible values are from 0-63

  ## LocationFromField* =  BoardIndex
  ## Encodes the location to move from in little endian rank-file mapping
  ## all possible values are from 0-63
  MoveTuple* = tuple[fro: BoardPosition, to: BoardPosition,
                     captured: Pieces, moving: AllPieces]
  FullMoveTuple* = object
    fro: BoardPosition
    to: BoardPosition
    captured: Pieces
    moving: AllPieces
    promo: Option[PromotionField]
    castle: Option[CastlingField]


const
  isPromoBit     = 29
  isEnPassantBit = 30
  nullMoveBit    = 31
  promotionField_mask     = 0xFFFFFFFFFFFFFFFC#'i32
  castlingField_mask      = 0xFFFFFFFFFFFFFFF3#'i32
  capturedPieceField_mask = 0xFFFFFFFFFFFFFF8F#'i32
  movingPieceField_mask   = 0xFFFFFFFFFFFFF87F#'i32
  locationToField_mask    = 0xFFFFFFFFFFFE07FF#'i32
  locationFromField_mask  = 0xFFFFFFFFFF81FFFF#'i32
  enPassantCapture_mask   = 0xFFFFFFFFE07FFFFF
  # isPromotionMove_mask    = (0xFFFFFFFFFFFFFFFF xor (1 shl isPromoBit))
  # isEnPassantMove_mask    = (0xFFFFFFFFFFFFFFFF xor (1 shl isEnPassantBit))

  PromotionFieldLookup = [
    Rook_Promotion,  Bishop_Promotion, Knight_Promotion, Queen_Promotion
  ]
  CastlingFieldLookup = [
    No_Castling, QueenSide_Castling, KingSide_Castling
  ]

  NULL_MOVE* = 1 shl nullMoveBit

##
## Generic method for setting fields in a `Move`
## `move`      : The move to be modified
## `field`     : The field to be set. As of 20/7/22 there are 6 fields that can be set. eg `CastlingField`
## `field_mask`: A number with all bits set apart from the ones corresponding the the field.
## `bit_offset`: Distance of the last bit of the field  from the last bit in the move
##                (How many bits do you have to shift a number representing the field to reach its position\
##                eg `CastlingField` has to be shifted by 2 bits to get to its location in the move)
## returns a new move with the field set
proc setField[T](move: Move, field: T, field_mask: int32, bit_offset: int): Move{.inline}=
  let
    tmp = bitand(move, field_mask)        ## \
                      ## The field mask is anded with the move to clear all bits corresponding to the field
    value = int32(field.ord) ## \
                      ## The numeric representation of the field
  return bitor(tmp, value shl bit_offset) ## \
                      ## The numeric representation is shifted to its position and merged with the move

## 
## Generic method for getting a particular field from a move
## `move`         : The move which you want to get the field from.
## `field_mask`   : A number with all bits set apart from the ones corresponding the the field.
## `field_lookup` : An array mapping the numeric value of a move back to the actual move itself
## `bit_offset`   : Distance of the last bit of the field  from the last bit in the move
## returns the extracted field
proc getField[T](move: Move, field_mask: int32, field_lookup: openArray[T], bit_offset: int): T{.inline}=
  let value = bitand(move, bitnot(field_mask)) ## \
                            ## Gets the value of the field by anding the inverse of its mask with the move  
  return field_lookup[value shr bit_offset]                   ## \
                            ## The actual type of the field is gotten from its numeric rep from the lookup

proc setIsPromotionMove*(move: Move): Move=
  return move or (1 shl isPromoBit)

proc getIsPromotionMove*(move: Move): bool=
  return (move and (1 shl isPromoBit))!=0

proc setIsEnPassantMove*(move: Move): Move=
  return move or (1 shl isEnPassantBit)

proc getIsEnPassantMove*(move: Move): bool=
  return (move and (1 shl isEnPassantBit))!=0


proc setPromotionField*(move: Move, field: PromotionField): Move=
  return setField(move, field, promotionField_mask, 0)
          .setIsPromotionMove()

proc getPromotionField*(move: Move): PromotionField=
  checkCondition(move.getIsPromotionMove(), "isPromotion move bit must be set")
  return getField(move, promotionField_mask, PromotionFieldLookup, 0)


proc setCastlingField*(move: Move, field: CastlingField): Move=
  return setField(move, field, castlingField_mask, 2)

proc getCastlingField*(move: Move): CastlingField=
  return getField(move, castlingField_mask, CastlingFieldLookup, 2)


proc setCapturedPieceField*(move: Move, field: Pieces): Move=
  ## If the field captured is a NULL_PIECE
  ## then there is no capture
  checkCondition(field != King, "cannot capture a king")
  return setField(move, field, capturedPieceField_mask, 4)

proc getCapturedPieceField*(move: Move): Pieces=
  result = getField(move, capturedPieceField_mask, PieceLookup, 4)
  checkCondition(result != King, "captured pieces cannot be a king")


proc setMovingPieceField*(move: Move, field: AllPieces): Move=
  return setField(move, field, movingPieceField_mask, 7)

proc getMovingPieceField*(move: Move): AllPieces=
  return getField(move, movingPieceField_mask, AllPiecesLookup, 7)


proc setLocationToField*(move: Move, field: ValidBoardPosition): Move=
  return setField(move, field, locationToField_mask, 11)

proc getLocationToField*(move: Move): ValidBoardPosition=
  return getField(move, locationToField_mask, BoardPositionLookup, 11)


proc setLocationFromField*(move: Move, field: ValidBoardPosition): Move=
  return setField(move, field, locationFromField_mask, 17)

proc getLocationFromField*(move: Move): ValidBoardPosition=
  return getField(move, locationFromField_mask, BoardPositionLookup, 17)


proc setEnPassantCaptureLocation*(move: Move, field: ValidBoardPosition): Move=
  checkCondition(calcRank(field) in [RANK_4,RANK5], "invalid enpassant position")
  return setField(move, field, enPassantCapture_mask, 23)
          .setIsEnPassantMove()

proc getEnPassantCaptureLocation*(move: Move): ValidBoardPosition=
  checkCondition(move.getIsEnPassantMove(), "isEnPassant move bit must be set")
  return getField(move, enPassantCapture_mask, BoardPositionLookup, 23)


proc setMainFields*(move: Move, movingPiece: AllPieces, capturedPiece: Pieces,
                    locationTo: ValidBoardPosition, locationFrom: ValidBoardPosition): Move=
  return move
          .setMovingPieceField(movingPiece)
          .setCapturedPieceField(capturedPiece)
          .setLocationToField(locationTo)
          .setLocationFromField(locationFrom)

proc setMainFields*(movetupl: MoveTuple): Move=
  return Move(0)
          .setMovingPieceField(movetupl.moving)
          .setCapturedPieceField(movetupl.captured)
          .setLocationToField(movetupl.to)
          .setLocationFromField(movetupl.fro)

proc isCastlingMove*(move: Move): bool=
  # No_Castling is the default, so non castling move have it set to that
  if move.getCastlingField()==No_Castling: return false

  # castling move must be done by a king and must have default values in every other field,
  # otherwise there's a bug
  checkCondition(move.getMovingPieceField() notin @[WhiteKing, BlackKing],
                 "Error: castling move must be done by a king!!")
  checkCondition(move.getLocationToField()==ValidBoardPosition.low,
                 "Error: castling move must have locationTo set to default!!")
  checkCondition(move.getLocationFromField()==ValidBoardPosition.low,
                 "Error: castling move must have locationFrom set to default!!")
  checkCondition(move.getCapturedPieceField()==Pieces.low,
                 "Error: castling move must have capturedPiece set to default!!")
  checkCondition(move.getPromotionField()==PromotionField.low,
                 "Error: castling move must have promotionField set to default!!")
  return true

proc prettyMove*(move: Move): MoveTuple=
  result.to        = move.getLocationToField()
  result.fro       = move.getLocationFromField()
  result.moving    = move.getMovingPieceField()
  result.captured  = move.getCapturedPieceField()

proc prettyMoveFull*(move: Move): FullMoveTuple=
  result.to        = move.getLocationToField()
  result.fro       = move.getLocationFromField()
  result.moving    = move.getMovingPieceField()
  result.captured  = move.getCapturedPieceField()
  if move.getIsPromotionMove(): result.promo = some(move.getPromotionField())
  if move.getCastlingField()!=No_Castling: result.castle =  some(move.getCastlingField())


#[
proc MakeMove*(board: BoardState, move: Move): BoardState=
  ## Return a modified board with `move` made
  result = board

  # pawn promotion
  if move.getIsPromotionMove():
    discard
  # pawn en passant
  elif move.getIsEnPassantMove():
    discard
  # king caslting
  elif move.getCastlingField()!=No_Castling:
    discard
  # normal captures
  elif move.getCapturedPieceField()!=NULL_PIECE:
    dicard
  # normal moves
  else:
    discard
    ]#
