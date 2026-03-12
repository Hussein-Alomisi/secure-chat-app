import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CustomAvatar extends StatelessWidget {
  final double radius;
  final String? imageUrl;
  final File? localImage;
  final String fallbackText;
  final Color backgroundColor;
  final Color foregroundColor;
  final double fontSize;
  final double? fontSizeFallback; // Use this or calculate from radius

  const CustomAvatar({
    super.key,
    required this.radius,
    this.imageUrl,
    this.localImage,
    required this.fallbackText,
    required this.backgroundColor,
    required this.foregroundColor,
    this.fontSize = 20.0,
    this.fontSizeFallback,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildImageOrFallback(),
    );
  }

  Widget _buildImageOrFallback() {
    if (localImage != null) {
      return Image.file(
        localImage!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => _buildFallback(),
        placeholder: (context, url) => Container( // Optional: loading shimmer or fallback
          color: backgroundColor,
          child: _buildFallback(),
        ),
      );
    } else {
      return _buildFallback();
    }
  }

  Widget _buildFallback() {
    return Center(
      child: Text(
        fallbackText.isNotEmpty ? fallbackText[0].toUpperCase() : '?',
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.bold,
          fontSize: fontSizeFallback ?? (radius * 0.8), // Auto size based on radius
        ),
      ),
    );
  }
}
