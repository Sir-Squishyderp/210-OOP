//practice.dart
import 'dart:math';

//create a 10x10 (n x n) grid
//with random numbers 1-10 in each cell

//we could List of Lists
//creating a grid of size n x n

class Grid {
  int size = 0;
  List<List<int>> realGrid = [];

  Grid(int s) : size = s, realGrid = [] {
    createGrid();
    cityPopulate();
  }

  List<List<int>>? createGrid() {
    Random rng = Random();
    List<List<int>> grid = [];
    for (int i = 0; i < size; i++) {
      List<int> row = [];
      for (int i = 0; i < size; i++) {
        row.add(rng.nextInt(10) + 1);
      }
      grid.add(row);
    }
    realGrid = grid;
    return grid;
  }

  void randomLocations() {
    Random rng = Random();
    int x = rng.nextInt(size);
    int y = rng.nextInt(size);
    int permX = x;
    int permY = y;
    if (realGrid[y][x] < 100) {
      realGrid[y][x] += 100;
    }
    x -= 2;
    y -= 2;
    for (int i = 0; i < 3; i++) {
      x += 1;
      y = permY - 2;
      for (int i = 0; i < 3; i++) {
        y += 1;
        if (x >= 0 && y >= 0 && x < realGrid.length && y < realGrid.length) {
          if (realGrid[y][x] < 100) {
            realGrid[y][x] += 25;
          }
        }
      }
    }
    x = permX;
    y = permY;
    x -= 3;
    y -= 3;
    for (int i = 0; i < 5; i++) {
      x += 1;
      y = permY - 3;
      for (int i = 0; i < 5; i++) {
        y += 1;
        if (x >= 0 && y >= 0 && x < realGrid.length && y < realGrid.length) {
          if (realGrid[y][x] < 100) {
            realGrid[y][x] += 25;
          }
        }
      }
    }
  }

  void cityPopulate() {
    randomLocations();
    randomLocations();
  }

  void printGrid() {
    for (int i = 0; i < realGrid.length; i++) {
      print("${realGrid[i]}");
    }
  }
}

class RiverGrid extends Grid {
  List<List<int>> realGrid = [];
  
  RiverGrid(int size) : super(size) {
    createGrid();
    cityPopulate();
    createRiver();
  }

  void valueCheck(int x, int y) {
    double z = realGrid[y][x] / 2;
    if (x - 1 != -1 && x + 1 < size) {
      realGrid[y][x - 1] += z.ceil();
      realGrid[y][x + 1] += z.ceil();
    } else if (x - 1 != -1) {
      realGrid[y][x - 1] += realGrid[y][x];
    } else if (x + 1 != size) {
      realGrid[y][x + 1] += realGrid[y][x];
    } else {
      print('Error, riverGrid size needs to be more than 1');
      return;
    }
  }

  void riverMaker(topX, topY, bottomX, bottomY) {
    List<int> midpoint = [
      ((topY + bottomY) / 2).round(),
      ((topX + bottomX) / 2).round(),
    ];

    if (midpoint[0] >= bottomY || midpoint[0] <= topY) {
      return;
    }

    //print("top: ${topX},${topY} bottom:${bottomX},${bottomY} mid=${midpoint[1]}, ${midpoint[0]}");
    valueCheck(midpoint[1], midpoint[0]);
    realGrid[midpoint[0]][midpoint[1]] = 0;
    
    riverMaker(topX, topY, midpoint[1], midpoint[0]);
    riverMaker(midpoint[1], midpoint[0], bottomX, bottomY);
  }

  void createRiver() {
    Random rng = Random();
    int top = rng.nextInt(size);
    int bottom = rng.nextInt(size);
    int topHeight = 0;
    int bottomHeight = size - 1;
    riverMaker(top, topHeight, bottom, bottomHeight);
    valueCheck(top, 0);
    valueCheck(bottom, size - 1);
    realGrid[0][top] = 0;
    realGrid[size - 1][bottom] = 0;
  }
}

void main() {
  RiverGrid one = RiverGrid(10);
  one.printGrid();
}
