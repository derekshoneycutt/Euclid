const path = require('path');
const webpack = require('webpack');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const HtmlWebpackPlugin = require('html-webpack-plugin');

const build_mode = 'production';

module.exports = {
    entry: './web/euclid.js',

    output: {
        path: path.resolve(__dirname, 'build/dist'),
        publicPath: '',
        filename: 'bundle.js'
    },

    module: {
        rules: [
            {
                test: /\.js$/,
                exclude: /(node_modules)/,
                use: {
                    loader: 'babel-loader',
                    options: {
                        presets: ['@babel/preset-env']
                    }
                }
            },
            {
                test: /\.(sa|sc|c)ss$/,
                use: [
                    {
                        loader: MiniCssExtractPlugin.loader
                    },
                    {
                        loader: 'css-loader'
                    },
                    {
                        loader: 'postcss-loader'
                    },
                    {
                        loader: 'sass-loader',
                        options: {
                            implementation: require('sass'),
                            webpackImporter: false,
                            sassOptions: {
                                includePaths: [
                                    path.resolve(__dirname, 'node_modules')
                                ]
                            }
                        }
                    }
                ]
            },
            {
                test: /\.(png|jpe?g|gif|svg)$/,
                use: [
                    {
                        loader: 'file-loader',
                        options: {
                            outputPath: 'images'
                        }
                    }
                ]
            }
        ]
    },

    plugins: [
        new MiniCssExtractPlugin({
            filename: 'bundle.css'
        }),

        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_001-Point.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_002-Line.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_003-LineExtremities.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_004-StraightLine.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_005-Surface.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_006-SurfaceExtremities.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_007-PlaneSurface.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_008-PlaneAngle.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Definitions_009-RectilinealAngle.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Postulates_index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_CommonNotions_index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_Propositions_index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_index.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_001-HighlightingPoints.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_002-MovingPoints.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_003-HighlightingLines.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_004-MovingLines.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_005-RotatingLines.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_006-ReflectingLines.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_007-IntersectingLines.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_008-MovingSurfaces.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_009-RotatingSurfaces.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_010-ReflectingSurfaces.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_011-HighlightingAngles.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_012-MovingAngles.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_013-RotatingAngles.html' }),
        new HtmlWebpackPlugin({ hash: true, template: './web/template.html', filename: 'ElementsBook1_AddedAxioms_014-ReflectingAngles.html' }),
    ],

    mode: build_mode
};
