import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
class ChessBoard extends StatefulWidget {
  const ChessBoard({super.key});

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  // Simple representation: row 0-7, col 0-7
  // You can later replace these strings with a Piece class
  late List<List<String?>> board;

  @override
  void initState() {
    super.initState();
    _initializeBoard();
  }

  void _initializeBoard() {
    // Initialize an 8x8 empty board
    board = List.generate(8, (_) => List.filled(8, null));

    // Example: Placing some pawns
    for (int i = 0; i < 8; i++) {
      board[1][i] = 'black_pawn';
      board[6][i] = 'white_pawn';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: Center(
        child: AspectRatio(
          aspectRatio: 1, // Keeps the board square
          child: GridView.builder(
            itemCount: 64,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
            ),
            itemBuilder: (context, index) {
              // Convert index (0-63) to row and column coordinates
              int row = index ~/ 8;
              int col = index % 8;

              // Logic to determine square color (checkerboard pattern)
              bool isLightSquare = (row + col) % 2 == 0;
            Color squareColor = isLightSquare 
              ? const Color(0xFFB5BDD3) // Darker, grayish-blue for "light" squares
              : const Color(0xFF486E8C);
              return Container(
                color: squareColor,
                child: _buildPiece(row, col),
              );
            },
          ),
        ),
      ),
    );
  }

Widget _buildPiece(int row, int col) {
  String? piece = board[row][col];
  if (piece == null) return const SizedBox();

  bool isWhite = piece.contains('white');

  return Center(
    child: Padding(
      padding: const EdgeInsets.all(5.0), 
      child: SvgPicture.asset(
        'assets/chess_elements/$piece.svg',
        fit: BoxFit.contain,
        // This forces the SVG to be pure white or pure black
        // It fixes visibility without needing shadows or circles
        colorFilter: ColorFilter.mode(
          isWhite ? Colors.white : Colors.black,
          BlendMode.srcIn,
        ),
      ),
    ),
  );
}
}