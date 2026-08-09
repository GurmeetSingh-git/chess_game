import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChessBoard extends StatefulWidget {
  const ChessBoard({super.key});

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  static const String baseUrl = 'http://localhost:8000';
  static const int aiDepth = 4;

  List<List<String?>> board = List.generate(8, (_) => List.filled(8, null));
  String currentTurn = 'white';
  bool isLoading = true;
  bool isAiThinking = false;
  String statusMessage = 'Loading board...';

  int? selectedRow;
  int? selectedCol;
  List<List<int>> validMoves = []; // highlighted valid destinations

  @override
  void initState() {
    super.initState();
    _fetchInitialBoard();
  }

  // ── API ────────────────────────────────────────────────

  Future<void> _fetchInitialBoard() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/initial-board'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw = data['board'] as List;
        setState(() {
          board = raw.map<List<String?>>((row) =>
              (row as List).map<String?>((c) => c as String?).toList()).toList();
          isLoading = false;
          statusMessage = 'Your turn (White)';
        });
      }
    } catch (e) {
      setState(() { isLoading = false; statusMessage = 'Server error'; });
    }
  }

  Future<void> _fetchAiMove() async {
    setState(() { isAiThinking = true; statusMessage = 'AI is thinking...'; });
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/best-move'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'board': board, 'color': 'black', 'depth': aiDepth}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'game_over') {
          setState(() { isAiThinking = false; statusMessage = 'Game Over!'; });
          return;
        }
        final fR = data['from']['row'] as int;
        final fC = data['from']['col'] as int;
        final tR = data['to']['row']   as int;
        final tC = data['to']['col']   as int;
        final promotion = data['promotion'] as String?;
        setState(() {
          board[tR][tC] = promotion != null
              ? 'black_$promotion'
              : board[fR][fC];
          board[fR][fC] = null;
          currentTurn = 'white';
          isAiThinking = false;
          statusMessage = 'Your turn (White)';
        });
      }
    } catch (e) {
      setState(() { isAiThinking = false; statusMessage = 'AI error'; });
    }
  }

  // ── MOVE VALIDATION ────────────────────────────────────

  List<List<int>> _getValidMoves(int row, int col) {
    final piece = board[row][col];
    if (piece == null) return [];

    final color = piece.contains('white') ? 'white' : 'black';
    final type  = piece.split('_').last;
    List<List<int>> moves = [];

    switch (type) {
      case 'pawn':   moves = _pawnMoves(row, col, color);   break;
      case 'knight': moves = _knightMoves(row, col, color); break;
      case 'bishop': moves = _slidingMoves(row, col, color, [[-1,-1],[-1,1],[1,-1],[1,1]]); break;
      case 'rook':   moves = _slidingMoves(row, col, color, [[-1,0],[1,0],[0,-1],[0,1]]); break;
      case 'queen':  moves = _slidingMoves(row, col, color, [[-1,-1],[-1,1],[1,-1],[1,1],[-1,0],[1,0],[0,-1],[0,1]]); break;
      case 'king':   moves = _kingMoves(row, col, color);   break;
    }

    // Filter moves that leave own king in check
    return moves.where((m) => !_moveLeavesKingInCheck(row, col, m[0], m[1], color)).toList();
  }

  bool _inBounds(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  String? _colorAt(int r, int c) {
    final p = board[r][c];
    if (p == null) return null;
    return p.contains('white') ? 'white' : 'black';
  }

  List<List<int>> _pawnMoves(int row, int col, String color) {
    final moves = <List<int>>[];
    final dir = color == 'white' ? -1 : 1;
    final startRow = color == 'white' ? 6 : 1;

    // Forward
    if (_inBounds(row + dir, col) && board[row + dir][col] == null) {
      moves.add([row + dir, col]);
      // Double push from start
      if (row == startRow && board[row + 2 * dir][col] == null) {
        moves.add([row + 2 * dir, col]);
      }
    }
    // Captures
    for (final dc in [-1, 1]) {
      final nr = row + dir;
      final nc = col + dc;
      if (_inBounds(nr, nc) && _colorAt(nr, nc) != null && _colorAt(nr, nc) != color) {
        moves.add([nr, nc]);
      }
    }
    return moves;
  }

  List<List<int>> _knightMoves(int row, int col, String color) {
    final moves = <List<int>>[];
    for (final offset in [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]]) {
      final nr = row + offset[0];
      final nc = col + offset[1];
      if (_inBounds(nr, nc) && _colorAt(nr, nc) != color) {
        moves.add([nr, nc]);
      }
    }
    return moves;
  }

  List<List<int>> _slidingMoves(int row, int col, String color, List<List<int>> dirs) {
    final moves = <List<int>>[];
    for (final d in dirs) {
      int nr = row + d[0];
      int nc = col + d[1];
      while (_inBounds(nr, nc)) {
        final targetColor = _colorAt(nr, nc);
        if (targetColor == null) {
          moves.add([nr, nc]);
        } else {
          if (targetColor != color) moves.add([nr, nc]); // capture
          break;
        }
        nr += d[0];
        nc += d[1];
      }
    }
    return moves;
  }

  List<List<int>> _kingMoves(int row, int col, String color) {
    final moves = <List<int>>[];
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = row + dr;
        final nc = col + dc;
        if (_inBounds(nr, nc) && _colorAt(nr, nc) != color) {
          moves.add([nr, nc]);
        }
      }
    }
    return moves;
  }

  // Simulate the move on a copy and check if own king is in check
  bool _moveLeavesKingInCheck(int fR, int fC, int tR, int tC, String color) {
    // Deep copy board
    final copy = board.map((r) => List<String?>.from(r)).toList();
    copy[tR][tC] = copy[fR][fC];
    copy[fR][fC] = null;

    // Find king position
    int kingRow = -1, kingCol = -1;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (copy[r][c] == '${color}_king') {
          kingRow = r; kingCol = c;
        }
      }
    }
    if (kingRow == -1) return false;

    return _isSquareAttackedOn(copy, kingRow, kingCol, color);
  }

  bool _isSquareAttackedOn(List<List<String?>> b, int row, int col, String byOpponentOf) {
    final enemy = byOpponentOf == 'white' ? 'black' : 'white';

    // Check knight attacks
    for (final o in [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]]) {
      final nr = row + o[0]; final nc = col + o[1];
      if (_inBounds(nr, nc) && b[nr][nc] == '${enemy}_knight') return true;
    }

    // Check sliding attacks (rook/queen — straight lines)
    for (final d in [[-1,0],[1,0],[0,-1],[0,1]]) {
      int nr = row + d[0]; int nc = col + d[1];
      while (_inBounds(nr, nc)) {
        final p = b[nr][nc];
        if (p != null) {
          if (p == '${enemy}_rook' || p == '${enemy}_queen') return true;
          break;
        }
        nr += d[0]; nc += d[1];
      }
    }

    // Check sliding attacks (bishop/queen — diagonals)
    for (final d in [[-1,-1],[-1,1],[1,-1],[1,1]]) {
      int nr = row + d[0]; int nc = col + d[1];
      while (_inBounds(nr, nc)) {
        final p = b[nr][nc];
        if (p != null) {
          if (p == '${enemy}_bishop' || p == '${enemy}_queen') return true;
          break;
        }
        nr += d[0]; nc += d[1];
      }
    }

    // Check pawn attacks
    final pawnDir = byOpponentOf == 'white' ? -1 : 1; // enemy pawns come from opposite dir
    for (final dc in [-1, 1]) {
      final nr = row - pawnDir;
      final nc = col + dc;
      if (_inBounds(nr, nc) && b[nr][nc] == '${enemy}_pawn') return true;
    }

    // Check king attacks (to avoid king moving next to king)
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = row + dr; final nc = col + dc;
        if (_inBounds(nr, nc) && b[nr][nc] == '${enemy}_king') return true;
      }
    }

    return false;
  }

  bool _isInCheck(String color) {
    int kingRow = -1, kingCol = -1;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (board[r][c] == '${color}_king') { kingRow = r; kingCol = c; }
      }
    }
    return _isSquareAttackedOn(board, kingRow, kingCol, color);
  }

  bool _isCheckmate(String color) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        if (_colorAt(r, c) == color && _getValidMoves(r, c).isNotEmpty) {
          return false;
        }
      }
    }
    return true;
  }

  // ── INTERACTION ────────────────────────────────────────

  void _onSquareTapped(int row, int col) {
    if (isAiThinking || currentTurn != 'white') return;

    final tappedPiece = board[row][col];

    if (selectedRow == null) {
      // Select a white piece
      if (tappedPiece != null && tappedPiece.startsWith('white')) {
        final moves = _getValidMoves(row, col);
        setState(() {
          selectedRow = row;
          selectedCol = col;
          validMoves = moves;
        });
      }
      return;
    }

    // Deselect same square
    if (selectedRow == row && selectedCol == col) {
      setState(() { selectedRow = null; selectedCol = null; validMoves = []; });
      return;
    }

    // Switch to another white piece
    if (tappedPiece != null && tappedPiece.startsWith('white')) {
      final moves = _getValidMoves(row, col);
      setState(() { selectedRow = row; selectedCol = col; validMoves = moves; });
      return;
    }

    // Check if destination is a valid move
    final isValid = validMoves.any((m) => m[0] == row && m[1] == col);
    if (!isValid) {
      // Invalid square — flash message but keep selection
      setState(() { statusMessage = 'Invalid move!'; });
      Future.delayed(const Duration(seconds: 1), () {
        setState(() { statusMessage = 'Your turn (White)'; });
      });
      return;
    }

    _applyPlayerMove(selectedRow!, selectedCol!, row, col);
  }

  void _applyPlayerMove(int fR, int fC, int tR, int tC) {
    final piece = board[fR][fC];
    if (piece == null) return;

    setState(() {
      // Pawn promotion → auto queen
      if (piece == 'white_pawn' && tR == 0) {
        board[tR][tC] = 'white_queen';
      } else {
        board[tR][tC] = piece;
      }
      board[fR][fC] = null;
      selectedRow = null;
      selectedCol = null;
      validMoves = [];
      currentTurn = 'black';
      statusMessage = 'AI is thinking...';
    });

    // Check if black is in checkmate after white's move
    if (_isCheckmate('black')) {
      setState(() { statusMessage = '🎉 Checkmate! You win!'; });
      return;
    }

    _fetchAiMove().then((_) {
      // After AI moves, check if white is in checkmate or check
      if (_isCheckmate('white')) {
        setState(() { statusMessage = '💀 Checkmate! AI wins!'; });
      } else if (_isInCheck('white')) {
        setState(() { statusMessage = '⚠️ You are in Check!'; });
      }
    });
  }

  void _resetGame() {
    setState(() {
      isLoading = true;
      selectedRow = null;
      selectedCol = null;
      validMoves = [];
      currentTurn = 'white';
    });
    _fetchInitialBoard();
  }

  // ── UI ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final boardSize = constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth
              : constraints.maxHeight - 80;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                color: isAiThinking ? Colors.orange[900] : Colors.grey[800],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isAiThinking)
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    if (isAiThinking) const SizedBox(width: 10),
                    Text(statusMessage,
                        style: const TextStyle(color: Colors.white, fontSize: 15)),
                  ],
                ),
              ),
              SizedBox(
                width: boardSize,
                height: boardSize,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildBoard(),
              ),
              TextButton.icon(
                onPressed: _resetGame,
                icon: const Icon(Icons.refresh, color: Colors.white70),
                label: const Text('New Game', style: TextStyle(color: Colors.white70)),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildBoard() {
    return GridView.builder(
      itemCount: 64,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemBuilder: (context, index) {
        final row = index ~/ 8;
        final col = index % 8;
        final isLight = (row + col) % 2 == 0;
        final isSelected = row == selectedRow && col == selectedCol;
        final isValidDest = validMoves.any((m) => m[0] == row && m[1] == col);

        Color squareColor;
        if (isSelected) {
          squareColor = Colors.yellow[600]!;
        } else if (isValidDest) {
          squareColor = board[row][col] != null
              ? Colors.red[400]!       // capturable enemy piece
              : Colors.green[400]!;    // empty valid square
        } else {
          squareColor = isLight ? const Color(0xFFB5BDD3) : const Color(0xFF486E8C);
        }

        return GestureDetector(
          onTap: () => _onSquareTapped(row, col),
          child: Container(
            color: squareColor,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildPiece(row, col),
                // Dot indicator for empty valid squares
                if (isValidDest && board[row][col] == null)
                  Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: Colors.green[700]!.withOpacity(0.8),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPiece(int row, int col) {
  final piece = board[row][col];
  if (piece == null) return const SizedBox.expand();

  final isWhite = piece.contains('white');
  final svgFile = piece.contains('knight') ? 'knight'
      : piece.contains('bishop')           ? 'chess_bishop'
      : piece.contains('rook')             ? 'chess_rook'
      : piece.contains('queen')            ? 'chess_queen'
      : piece.contains('king')             ? 'chess_king'
      :                                      'chess_pawn';

  return LayoutBuilder(
    builder: (context, constraints) {
      // Use 75% of the square size so every piece is proportional
      final size = constraints.maxWidth * 0.75;
      return Center(
        child: SizedBox(
          width: size,
          height: size,
          child: SvgPicture.asset(
            'assets/chess_elements/$svgFile.svg',
            width: size,
            height: size,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(
              isWhite ? const Color(0xFFFFFAF0) : const Color(0xFF111111),
              BlendMode.srcIn,
            ),
          ),
        ),
      );
    },
  );
}
}